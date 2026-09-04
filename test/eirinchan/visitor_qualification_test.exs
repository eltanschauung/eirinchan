defmodule Eirinchan.VisitorQualificationTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.BrowserIdentity
  alias Eirinchan.Statistics
  alias Eirinchan.VisitorQualification

  @now 1_800_000_000
  @config %{
    visitor_minimum_age_seconds: 60,
    visitor_identity_churn_limit: 3,
    visitor_identity_churn_window_seconds: 600
  }
  @metrics ~w(
    visitors.identities.issued
    visitors.identities.returned_early
    visitors.identities.qualified
    visitors.identities.excluded_churn
    visitors.identities.excluded_crawler
  )

  setup do
    :ets.delete_all_objects(VisitorQualification.identity_table())
    :ets.delete_all_objects(VisitorQualification.bucket_table())

    Statistics.create_counter_table()
    hour = div(@now, 3_600) * 3_600
    Enum.each(@metrics, &:ets.delete(Statistics.counter_table(), {hour, &1}))
    :ok
  end

  test "client buckets are stable without retaining their inputs" do
    features = ["Mozilla/5.0", "en-US", ~s("Chromium";v="140"), "Linux", "?0"]

    bucket = VisitorQualification.client_bucket("198.51.100.10", features)

    assert byte_size(bucket) == 43
    assert bucket == VisitorQualification.client_bucket("198.51.100.10", features)
    refute bucket == VisitorQualification.client_bucket("198.51.100.11", features)
    refute bucket == VisitorQualification.client_bucket("198.51.100.10", ["different"])
    refute String.contains?(bucket, "198.51.100.10")
    refute String.contains?(bucket, "Mozilla")
  end

  test "a new identity must survive the minimum age before it qualifies" do
    browser_ref = browser_ref("minimum-age")
    bucket = client_bucket("minimum-age")

    assert :ok =
             VisitorQualification.record_issue(browser_ref, bucket, @now,
               now: @now,
               config: @config
             )

    assert {:pending, :minimum_age} =
             VisitorQualification.qualify(browser_ref, @now,
               now: @now + 59,
               config: @config
             )

    assert :qualified =
             VisitorQualification.qualify(browser_ref, @now,
               now: @now + 60,
               config: @config
             )

    assert [{^browser_ref, ^bucket, @now, :qualified}] =
             :ets.lookup(VisitorQualification.identity_table(), browser_ref)
  end

  test "rapid identity rotation excludes every pending identity in the client bucket" do
    bucket = client_bucket("churn")

    browser_refs =
      for index <- 1..4 do
        browser_ref = browser_ref("churn-#{index}")

        assert :ok =
                 VisitorQualification.record_issue(browser_ref, bucket, @now + index,
                   now: @now + index,
                   config: @config
                 )

        browser_ref
      end

    for browser_ref <- browser_refs do
      assert {:excluded, :identity_churn} =
               VisitorQualification.qualify(browser_ref, @now,
                 now: @now + 64,
                 config: @config
               )
    end
  end

  test "the churn filter remains isolated between anonymous client buckets" do
    entries =
      for index <- 1..8 do
        bucket = client_bucket("isolated-#{index}")
        browser_ref = browser_ref("isolated-#{index}")

        VisitorQualification.record_issue(browser_ref, bucket, @now,
          now: @now,
          config: @config
        )

        browser_ref
      end

    for browser_ref <- entries do
      assert :qualified =
               VisitorQualification.qualify(browser_ref, @now,
                 now: @now + 60,
                 config: @config
               )
    end
  end

  test "crawler exclusion survives a later browser-like request" do
    browser_ref = browser_ref("crawler")
    bucket = client_bucket("crawler")

    VisitorQualification.record_issue(browser_ref, bucket, @now, now: @now, config: @config)
    assert :ok = VisitorQualification.exclude_crawler(browser_ref, now: @now + 1)

    assert {:excluded, :crawler} =
             VisitorQualification.qualify(browser_ref, @now,
               now: @now + 60,
               config: @config
             )
  end

  test "crawler exclusion supersedes an identity that had already qualified" do
    browser_ref = browser_ref("qualified-crawler")
    bucket = client_bucket("qualified-crawler")

    VisitorQualification.record_issue(browser_ref, bucket, @now, now: @now, config: @config)

    assert :qualified =
             VisitorQualification.qualify(browser_ref, @now,
               now: @now + 60,
               config: @config
             )

    assert :ok = VisitorQualification.exclude_crawler(browser_ref, now: @now + 61)

    assert {:excluded, :crawler} =
             VisitorQualification.qualify(browser_ref, @now,
               now: @now + 62,
               config: @config
             )
  end

  test "concurrent issue recording produces an exact bounded churn count" do
    bucket = client_bucket("concurrent")

    browser_refs = Enum.map(1..64, &browser_ref("concurrent-#{&1}"))

    browser_refs
    |> Task.async_stream(
      &VisitorQualification.record_issue(&1, bucket, @now,
        now: @now,
        config: @config
      ),
      max_concurrency: 32,
      ordered: false
    )
    |> Enum.each(fn result -> assert result == {:ok, :ok} end)

    assert [{{^bucket, _minute}, 64}] =
             :ets.lookup(VisitorQualification.bucket_table(), {bucket, div(@now, 60)})

    browser_refs
    |> Task.async_stream(
      &VisitorQualification.qualify(&1, @now,
        now: @now + 60,
        config: @config
      ),
      max_concurrency: 32,
      ordered: false
    )
    |> Enum.each(fn result -> assert result == {:ok, {:excluded, :identity_churn}} end)
  end

  test "zero values disable age and churn qualification" do
    config = %{
      visitor_minimum_age_seconds: 0,
      visitor_identity_churn_limit: 0,
      visitor_identity_churn_window_seconds: 600
    }

    bucket = client_bucket("disabled")

    for index <- 1..8 do
      browser_ref = browser_ref("disabled-#{index}")
      VisitorQualification.record_issue(browser_ref, bucket, @now, now: @now, config: config)

      assert :qualified =
               VisitorQualification.qualify(browser_ref, @now, now: @now, config: config)
    end
  end

  test "pruning removes expired identity and bucket state without stopping the tracker" do
    issued_at = System.system_time(:second) - 3 * 86_400
    browser_ref = browser_ref("expired")
    bucket = client_bucket("expired")

    VisitorQualification.record_issue(browser_ref, bucket, issued_at, now: issued_at)
    assert :ets.lookup(VisitorQualification.identity_table(), browser_ref) != []

    assert :ok = VisitorQualification.prune()
    assert :ets.lookup(VisitorQualification.identity_table(), browser_ref) == []
    assert :ets.lookup(VisitorQualification.bucket_table(), {bucket, div(issued_at, 60)}) == []
    assert Process.alive?(Process.whereis(VisitorQualification))
  end

  test "records bounded aggregate counters once per identity transition" do
    browser_ref = browser_ref("metrics")
    bucket = client_bucket("metrics")
    hour = div(@now, 3_600) * 3_600

    VisitorQualification.record_issue(browser_ref, bucket, @now, now: @now, config: @config)

    for _attempt <- 1..3 do
      assert {:pending, :minimum_age} =
               VisitorQualification.qualify(browser_ref, @now,
                 now: @now + 30,
                 config: @config
               )
    end

    assert :qualified =
             VisitorQualification.qualify(browser_ref, @now,
               now: @now + 60,
               config: @config
             )

    assert [{{^hour, "visitors.identities.issued"}, 1}] =
             :ets.lookup(Statistics.counter_table(), {hour, "visitors.identities.issued"})

    assert [{{^hour, "visitors.identities.returned_early"}, 1}] =
             :ets.lookup(Statistics.counter_table(), {
               hour,
               "visitors.identities.returned_early"
             })

    assert [{{^hour, "visitors.identities.qualified"}, 1}] =
             :ets.lookup(Statistics.counter_table(), {hour, "visitors.identities.qualified"})
  end

  defp browser_ref(suffix), do: BrowserIdentity.reference("visitor-qualification-#{suffix}")

  defp client_bucket(suffix) do
    VisitorQualification.client_bucket("203.0.113.10", ["browser-#{suffix}"])
  end
end
