defmodule Eirinchan.Tripcode do
  @moduledoc false

  @php_tripcode_script """
  $name = $argv[1] ?? "";
  $secure_trip_salt = $argv[2] ?? "";
  $custom_tripcodes = json_decode($argv[3] ?? "{}", true);

  if (!is_array($custom_tripcodes)) {
      $custom_tripcodes = array();
  }

  if (!preg_match('/^([^#]+)?(##|#)(.+)$/u', $name, $match)) {
      echo json_encode(array('name' => $name, 'tripcode' => null));
      exit(0);
  }

  $display_name = $match[1];
  $secure = $match[2] === '##';
  $trip = $match[3];

  $trip = mb_convert_encoding($trip, 'Shift_JIS', 'UTF-8');
  $salt = substr($trip . 'H..', 1, 2);
  $salt = preg_replace('/[^.-z]/', '.', $salt);
  $salt = strtr($salt, ':;<=>?@[\\\\]^_`', 'ABCDEFGabcdef');

  if ($secure) {
      $custom_key = "##" . $trip;

      if (isset($custom_tripcodes[$custom_key])) {
          $tripcode = $custom_tripcodes[$custom_key];
      } else {
          $tripcode = '!!' . substr(
              crypt(
                  $trip,
                  str_replace(
                      '+',
                      '.',
                      '_..A.' . substr(base64_encode(sha1($trip . $secure_trip_salt, true)), 0, 4)
                  )
              ),
              -10
          );
      }
  } else {
      $custom_key = "#" . $trip;

      if (isset($custom_tripcodes[$custom_key])) {
          $tripcode = $custom_tripcodes[$custom_key];
      } else {
          $tripcode = '!' . substr(crypt($trip, $salt), -10);
      }
  }

  echo json_encode(array('name' => $display_name, 'tripcode' => $tripcode));
  """

  def split_name_and_tripcode(name, config) when is_binary(name) do
    case Regex.run(~r/^(.*?)(##?)(.+)$/u, name) do
      [_, _display_name, _marker, _secret] ->
        run_tripcode_command(name, config)

      _ ->
        {trim_to_nil(name), nil}
    end
  end

  def split_name_and_tripcode(name, _config), do: {name, nil}

  defp run_tripcode_command(name, config) do
    php = System.find_executable("php")

    if is_binary(php) do
      secure_trip_salt = config |> Map.get(:secure_trip_salt, "") |> to_string()
      custom_tripcodes = config |> Map.get(:custom_tripcode, %{}) |> Jason.encode!()

      case System.cmd(php, ["-r", @php_tripcode_script, name, secure_trip_salt, custom_tripcodes],
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          case Jason.decode(output) do
            {:ok, %{"name" => display_name, "tripcode" => tripcode}} ->
              {trim_to_nil(display_name), trim_to_nil(tripcode)}

            _ ->
              {trim_to_nil(name), nil}
          end

        _ ->
          {trim_to_nil(name), nil}
      end
    else
      {trim_to_nil(name), nil}
    end
  end

  defp trim_to_nil(nil), do: nil

  defp trim_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim_to_nil(value), do: value
end
