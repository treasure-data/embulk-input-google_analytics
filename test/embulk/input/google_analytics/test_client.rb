require "embulk"
Embulk.setup

require "embulk/input/google_analytics"
require "override_assert_raise"
require "fixture_helper"

module Embulk
  module Input
    module GoogleAnalytics
      class TestClient < Test::Unit::TestCase
        include OverrideAssertRaise
        include FixtureHelper

        sub_test_case "canonical_column_names" do
          setup do
            conf = valid_config["in"]
            @task = task(embulk_config(conf))
            @client = Client.new(@task)
          end

          test "XX column names should be expanded" do
            columns = @client.canonical_column_names([
              {id: "foo"},
              {id: "baXXr", attributes: {minTemplateIndex: 1, maxTemplateIndex: 3}},
              {id: "bazXX", attributes: {minTemplateIndex: 1, maxTemplateIndex: 3}},
              {id: "jarXX", attributes: {minTemplateIndex: 1, maxTemplateIndex: 3, premiumMinTemplateIndex: 1, premiumMaxTemplateIndex: 5}},
            ])
            expected_names = %w(
              foo ba1r ba2r ba3r baz1 baz2 baz3
              jar1 jar2 jar3 jar4 jar5
            )

            assert_equal expected_names, columns.map{|col| col[:id]}
          end
        end

        sub_test_case "get_profile" do
          setup do
            conf = valid_config["in"]
            @task = task(embulk_config(conf))
            @client = Client.new(@task)
          end

          test "find view_id profile" do
            target_profile = {
              id: @task["view_id"],
            }

            mock(@client).get_all_profiles do
              {
                items: [
                  { id: 1 },
                  target_profile,
                  { id: 2 },
                ]
              }
            end

            assert_equal target_profile, @client.get_profile
          end

          test "raise ConfigError when view_id is not found" do
            mock(@client).get_all_profiles do
              {
                items: [
                  { id: 1 },
                  { id: 2 },
                ]
              }
            end

            assert_raise(Embulk::ConfigError) do
              @client.get_profile
            end
          end
        end

        sub_test_case "build_report_request" do
          setup do
            conf = valid_config["in"]
            @task = task(embulk_config(conf))
            @client = Client.new(@task)
          end

          test "page_token = nil" do
            req = @client.build_report_request
            expected = [
              {
                view_id: "101111111",
                dimensions: [
                  {name: "ga:dateHour"}, {name: "ga:browser"}
                ],
                metrics: [
                  {expression: "ga:visits"}, {expression: "ga:pageviews"}
                ],
                include_empty_rows: true,
                page_size: 10000
              }
            ]
            assert_equal expected, req
          end

          test "page_token = 123" do
            req = @client.build_report_request(123)
            expected = [
              {
                view_id: "101111111",
                dimensions: [
                  {name: "ga:dateHour"}, {name: "ga:browser"}
                ],
                metrics: [
                  {expression: "ga:visits"}, {expression: "ga:pageviews"}
                ],
                include_empty_rows: true,
                page_size: 10000,
                page_token: 123
              }
            ]
            assert_equal expected, req
          end

          test "date range given" do
            conf = valid_config["in"]
            conf["start_date"] = "2000-01-01"
            conf["end_date"] = "2000-01-07"
            task = task(embulk_config(conf))
            client = Client.new(task)
            req = client.build_report_request

            expected = [
              {
                view_id: "101111111",
                dimensions: [
                  {name: "ga:dateHour"}, {name: "ga:browser"}
                ],
                metrics: [
                  {expression: "ga:visits"}, {expression: "ga:pageviews"}
                ],
                include_empty_rows: true,
                page_size: 10000,
                date_ranges: [
                  {
                    start_date: conf["start_date"],
                    end_date: conf["end_date"],
                  }
                ]
              }
            ]
            assert_equal expected, req
          end
        end

        sub_test_case "time_parse_with_profile_timezone" do
          setup do
            conf = valid_config["in"]
            conf["time_series"] = time_series
            @client = Client.new(task(embulk_config(conf)))
          end

          sub_test_case "dateHour" do
            setup do
              stub(@client).get_profile { {timezone: "America/Los_Angeles" } }
            end

            test "in dst" do
              time = @client.time_parse_with_profile_timezone("2016060122")
              assert_equal Time.parse("2016-06-01 22:00:00 -07:00"), time
            end

            test "not in dst" do
              time = @client.time_parse_with_profile_timezone("2016010122")
              assert_equal Time.parse("2016-01-01 22:00:00 -08:00"), time
            end

            sub_test_case "Logging invalid values" do
              setup do
                @logger = Logger.new(File::NULL)
                stub(Embulk).logger { @logger }
              end

              test "empty" do
                assert_raise Embulk::DataError.new(%Q|Failed to parse ga:dateHour data. The value is ''(String) and it doesn't match with '%Y%m%d%H'.|) do
                  @client.time_parse_with_profile_timezone("")
                end
              end
            end

            def time_series
              "ga:dateHour"
            end
          end

          sub_test_case "date" do
            setup do
              stub(@client).get_profile { {timezone: "America/Los_Angeles" } }
            end

            test "in dst" do
              time = @client.time_parse_with_profile_timezone("20160601")
              assert_equal Time.parse("2016-06-01 00:00:00 PDT"), time
            end

            test "not in dst" do
              time = @client.time_parse_with_profile_timezone("2016010122")
              assert_equal Time.parse("2016-01-01 00:00:00 PST"), time
            end

            sub_test_case "Logging invalid values" do
              setup do
                @logger = Logger.new(File::NULL)
                stub(Embulk).logger { @logger }
              end

              test "empty" do
                assert_raise Embulk::DataError.new(%Q|Failed to parse ga:date data. The value is ''(String) and it doesn't match with '%Y%m%d'.|) do
                  @client.time_parse_with_profile_timezone("")
                end
              end
            end

            def time_series
              "ga:date"
            end
          end
        end

        sub_test_case "auth" do
          setup do
            conf = valid_config["in"]
            mute_logger
            @client = Client.new(task(embulk_config(conf)))
          end

          sub_test_case "retry" do
            def should_retry
              mock(Google::Auth::ServiceAccountCredentials).make_creds(anything).times(retryer.config.limit + 1) { raise error }
              assert_raise do
                @client.auth
              end
            end

            def should_not_retry
              mock(Google::Auth::ServiceAccountCredentials).make_creds(anything).times(1) { raise error }
              assert_raise do
                @client.auth
              end
            end

            setup do
              # stub(Google::Auth::ServiceAccountCredentials).make_creds { raise error }
            end

            sub_test_case "Server error (5xx)" do
              def error
                Google::Apis::ServerError.new("error")
              end

              test "should retry" do
                should_retry
              end
            end

            sub_test_case "Rate Limit" do
              def error
                Google::Apis::RateLimitError.new("error")
              end

              test "should retry" do
                should_retry
              end
            end

            sub_test_case "Auth Error" do
              def error
                Google::Apis::AuthorizationError.new("error")
              end

              test "should not retry" do
                should_not_retry
              end
            end
          end
        end

        sub_test_case "too_early_data?" do
          def stub_timezone(client)
            stub(client).get_profile { {timezone: "America/Los_Angeles" } }
            stub(client).swap_time_zone do |block|
              stub(Time.zone).now { @now }
              block.call
            end
          end

          test "ga:dateHour" do
            conf = valid_config["in"]
            conf["time_series"] = "ga:dateHour"
            client = Client.new(task(embulk_config(conf)))
            @now = Time.parse("2016-06-01 05:00:00 PDT")
            stub_timezone(client)

            assert_equal false, client.too_early_data?("2016060104")
            assert_equal true , client.too_early_data?("2016060105")
            assert_equal true , client.too_early_data?("2016060106")
          end

          test "ga:date" do
            conf = valid_config["in"]
            conf["time_series"] = "ga:date"
            client = Client.new(task(embulk_config(conf)))
            @now = Time.parse("2016-06-03 05:00:00 PDT")
            stub_timezone(client)

            assert_equal false, client.too_early_data?("20160601")
            assert_equal false, client.too_early_data?("20160602")
            assert_equal true , client.too_early_data?("20160603")
          end
        end

        sub_test_case "each_report_row" do
          setup do
            conf = valid_config["in"]
            @task = task(embulk_config(conf))
            @client = Client.new(@task)
            stub(@client).get_profile { {timezone: "Asia/Tokyo"} }
            @logger = Logger.new(File::NULL)
            stub(Embulk).logger { @logger }
          end

          test "without pagination" do
            stub(@client).get_reports { report }
            fetched_rows = []
            @client.each_report_row do |row|
              fetched_rows << row
            end

            expected = [
              {
                "ga:dateHour" => @client.time_parse_with_profile_timezone("2016060120"),
                "ga:browser" => "curl",
                "ga:visits" => "1",
                "ga:pageviews" => "1",
                "view_id" => @task["view_id"],
              },
              {
                "ga:dateHour" => @client.time_parse_with_profile_timezone("2016060121"),
                "ga:browser" => "curl",
                "ga:visits" => "2",
                "ga:pageviews" => "2",
                "view_id" => @task["view_id"],
              },
              {
                "ga:dateHour" => @client.time_parse_with_profile_timezone("2016060122"),
                "ga:browser" => "curl",
                "ga:visits" => "3",
                "ga:pageviews" => "3",
                "view_id" => @task["view_id"],
              },
            ]
            assert_equal expected, fetched_rows
          end

          test "with pagination" do
            next_page_token = "10000"
            mock(@client).get_reports(nil) { report_with_pages }
            mock(@client).get_reports(next_page_token) { report }
            fetched_rows = []
            @client.each_report_row do |row|
              fetched_rows << row
            end
            assert_equal 6, fetched_rows.length
          end

          sub_test_case "logger" do
            test "with empty rows" do
              response = report.dup
              response[:reports].first[:data][:rows] = []
              response[:reports].first[:data][:row_count] = 0
              stub(@client).get_reports { response }

              mock(@logger).warn("Result has 0 rows.")
              @client.each_report_row {}
            end

            test "without rows" do
              response = report.dup
              response[:reports].first[:data].delete(:rows)
              stub(@client).get_reports { response }

              mock(@logger).warn("Result doesn't contain rows.")
              @client.each_report_row {}
            end
          end

          def report_with_pages
            response = report.dup
            response[:reports].first[:next_page_token] = "10000"
            response
          end

          def report
            json = fixture_read("reports.json")
            JSON.parse(json, symbolize_names: true)
          end
        end

        def task(config)
          Plugin.task_from_config(config)
        end

        def valid_config
          fixture_load("valid.yml")
        end

        def embulk_config(hash)
          Embulk::DataSource.new(hash)
        end

        def mute_logger
          @logger = Logger.new(File::NULL)
          stub(Embulk).logger { @logger }
        end

        def retryer
          @client.retryer
        end
      end
    end
  end
end
