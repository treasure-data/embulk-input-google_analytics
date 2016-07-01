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

            def time_series
              "ga:date"
            end
          end
        end

        sub_test_case "each_report_row" do
          setup do
            conf = valid_config["in"]
            @client = Client.new(task(embulk_config(conf)))
            stub(@client).get_profile { {timezone: "Asia/Tokyo"} }
            stub(Embulk).logger { Logger.new(File::NULL) }
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
              },
              {
                "ga:dateHour" => @client.time_parse_with_profile_timezone("2016060121"),
                "ga:browser" => "curl",
                "ga:visits" => "2",
                "ga:pageviews" => "2",
              },
              {
                "ga:dateHour" => @client.time_parse_with_profile_timezone("2016060122"),
                "ga:browser" => "curl",
                "ga:visits" => "3",
                "ga:pageviews" => "3",
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

          def report_with_pages
            response = report.dup
            response[:reports].first[:next_page_token] = "10000"
            response
          end

          def report
            {
              reports: [
                {
                  column_header: {
                    dimensions: [
                      "ga:dateHour", "ga:browser"
                    ],
                    metric_header: {
                      metric_header_entries: [
                        {type: "INTEGER", name: "ga:visits"},
                        {type: "INTEGER", name: "ga:pageviews"},
                      ]
                    }
                  },
                  data: {
                    row_count: 3,
                    rows: [
                      {
                        metrics: [
                          { values: ["1","1"] },
                        ],
                        dimensions: [
                          "2016060120", "curl"
                        ]
                      },
                      {
                        metrics: [
                          { values: ["2","2"] },
                        ],
                        dimensions: [
                          "2016060121", "curl"
                        ]
                      },
                      {
                        metrics: [
                          { values: ["3","3"] },
                        ],
                        dimensions: [
                          "2016060122", "curl"
                        ]
                      },
                    ]
                  }
                }
              ]
            }
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
      end
    end
  end
end
