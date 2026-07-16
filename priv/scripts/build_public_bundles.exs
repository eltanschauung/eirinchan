unless Code.ensure_loaded?(EirinchanWeb.JsBundles) do
  Code.require_file("../../lib/eirinchan_web/js_bundles.ex", __DIR__)
end

alias EirinchanWeb.JsBundles

project_root = Path.expand("../..", __DIR__)
node = System.find_executable("node") || raise "Node.js is required to build JavaScript assets"
minifier = Path.join(__DIR__, "minify_js.mjs")

unless File.regular?(minifier) do
  raise "missing JavaScript minifier: #{minifier}"
end

JsBundles.validate!(project_root)

run_minifier = fn label, public_output, source_paths ->
  destination = Path.expand(JsBundles.output_path(public_output), project_root)
  sources = Enum.map(source_paths, &Path.expand(&1, project_root))

  {output, status} =
    System.cmd(
      node,
      [minifier, "--output", destination, "--label", label, "--" | sources],
      cd: project_root,
      stderr_to_stdout: true
    )

  if status != 0 do
    raise "JavaScript minification failed for #{label}:\n#{output}"
  end

  output
  |> String.trim()
  |> Jason.decode!()
  |> Map.put("output", JsBundles.output_path(public_output))
  |> Map.put("sources", source_paths)
  |> Map.put("public_path", "/" <> public_output)
end

maintained_entries =
  JsBundles.maintained_outputs()
  |> Enum.sort_by(fn {output, _source} -> output end)
  |> Enum.map(fn {output, source} ->
    run_minifier.("maintained:#{output}", output, [source])
  end)

bundle_entries =
  Enum.map(JsBundles.all_bundle_keys(), fn bundle_key ->
    public_output = JsBundles.bundle_url(bundle_key) |> String.trim_leading("/")
    sources = bundle_key |> JsBundles.sources_for() |> Enum.map(&JsBundles.source_path/1)
    run_minifier.("bundle:#{bundle_key}", public_output, sources)
  end)

manifest = %{
  "format" => 1,
  "generator" => "priv/scripts/build_public_bundles.exs",
  "maintained" => maintained_entries,
  "bundles" => bundle_entries
}

manifest_path = Path.join(project_root, "priv/static/js/bundle-manifest.json")
temporary_path = manifest_path <> ".tmp-#{System.unique_integer([:positive])}"
File.write!(temporary_path, Jason.encode_to_iodata!(manifest, pretty: true))

case File.rename(temporary_path, manifest_path) do
  :ok ->
    :ok

  {:error, reason} when reason in [:eacces, :eexist] ->
    # Windows does not replace an existing destination with File.rename/2.
    File.rm!(manifest_path)
    File.rename!(temporary_path, manifest_path)

  {:error, reason} ->
    File.rm(temporary_path)
    raise File.Error, reason: reason, action: "rename", path: manifest_path
end

IO.puts(
  "Built #{length(maintained_entries)} maintained JavaScript files and " <>
    "#{length(bundle_entries)} minified bundles."
)
