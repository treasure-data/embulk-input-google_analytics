require "embulk"
Embulk.setup

require "embulk/input/google_analytics"
require "active_support/core_ext/time"
require "override_assert_raise"
require "fixture_helper"

module Embulk
  module Input
    module GoogleAnalytics
      class TestPlugin < Test::Unit::TestCase
        include OverrideAssertRaise
        include FixtureHelper
        DEFAULT_TIMEZONE = "America/Los_Angeles"
        sub_test_case ".transaction" do
          setup do
            any_instance_of(Client) do |klass|
              stub(klass).get_columns_list do
                [
                  {id: "ga:dateHour", attributes: {dataType: "STRING"}},
                  {id: "ga:date", attributes: {dataType: "STRING"}},
                  {id: "ga:browser", attributes: {dataType: "STRING"}},
                  {id: "ga:visits", attributes: {dataType: "INTEGER"}},
                  {id: "ga:pageviews", attributes: {dataType: "INTEGER"}},
                ]
              end
            end
          end

          test "not raised exception" do
            stub(Plugin).resume { Hash.new }
            assert_nothing_raised do
              Plugin.transaction(embulk_config(valid_config["in"]))
            end
          end

          test "assemble expected columns" do
            columns = [
              Embulk::Column.new(nil, "date_hour", :timestamp),
              Embulk::Column.new(nil, "browser", :string),
              Embulk::Column.new(nil, "visits", :long),
              Embulk::Column.new(nil, "pageviews", :long),
              Embulk::Column.new(nil, "view_id", :string),
            ]
            mock(Plugin).resume(anything, columns, 1)
            Plugin.transaction(embulk_config(valid_config["in"]))
          end

          sub_test_case "raise error when unknown column given" do
            setup { stub(Plugin).resume { Hash.new } }

            test "for dimensions" do
              conf = valid_config["in"]
              conf["dimensions"] << unknown_col_name
              assert_raise(Embulk::ConfigError.new(expected_message)) do
                Plugin.transaction(embulk_config(conf))
              end
            end

            test "for metrics" do
              conf = valid_config["in"]
              conf["metrics"] << unknown_col_name
              assert_raise(Embulk::ConfigError.new(expected_message)) do
                Plugin.transaction(embulk_config(conf))
              end
            end

            test "for time_series" do
              conf = valid_config["in"]
              conf["time_series"] = unknown_col_name
              message = "Unknown time_series 'ga:foooooo'. Use 'ga:dateHour' or 'ga:date'"
              assert_raise(Embulk::ConfigError.new(message)) do
                Plugin.transaction(embulk_config(conf))
              end
            end

            test "missing client_id params for oauth" do
              conf = valid_config_oauth["in"]
              conf.delete("client_id")
              assert_raise(Embulk::ConfigError.new(oauth_expect_message)) do
                Plugin.transaction(embulk_config(conf))
              end
            end

            test "missing client_secret params for oauth" do
              conf = valid_config_oauth["in"]
              conf.delete('client_secret')
              assert_raise(Embulk::ConfigError.new(oauth_expect_message)) do
                Plugin.transaction(embulk_config(conf))
              end
            end

            test "missing refresh_token params for oauth" do
              conf = valid_config_oauth["in"]
              conf.delete("refresh_token")
              assert_raise(Embulk::ConfigError.new(unknown_auth_method_message)) do
                Plugin.transaction(embulk_config(conf))
              end
            end

            test "missing json_key_content params for oauth" do
              conf = valid_config["in"]
              conf.delete("json_key_content")
              assert_raise(Embulk::ConfigError.new(unknown_auth_method_message)) do
                Plugin.transaction(embulk_config(conf))
              end
            end

            test "invalid json_key_content params for oauth" do
              conf = valid_config["in"]
              # Empty json_key_content
              conf["json_key_content"] = ""
              message = "json_key_content is not a valid JSON object"
              assert_raise(Embulk::ConfigError.new(message)) do
                Plugin.transaction(embulk_config(conf))
              end
              # null json_key_content
              conf["json_key_content"] = "null"
              assert_raise(Embulk::ConfigError.new(message)) do
                Plugin.transaction(embulk_config(conf))
              end
              # Not a string json_key_content
              conf["json_key_content"] = nil
              assert_raise(Embulk::ConfigError.new(message)) do
                Plugin.transaction(embulk_config(conf))
              end
            end

            def unknown_auth_method_message
              "Unknown Authentication method ''."
            end

            def oauth_expect_message
              "client_id, client_secret and refresh_token are required when using Oauth authentication"
            end

            def unknown_col_name
              "ga:foooooo"
            end

            def expected_message
              "Unknown metric/dimension '#{unknown_col_name}'"
            end
          end

          sub_test_case "type conversion" do
            setup do
              any_instance_of(Client) do |klass|
                stub(klass).get_columns_list do
                  [
                    {id: "ga:dateHour", attributes: {dataType: "STRING"}},
                    {id: "ga:itemsPerPurchase", attributes: {dataType: "FLOAT"}},
                    {id: "ga:visits", attributes: {dataType: "INTEGER"}},
                    {id: "ga:CPM", attributes: {dataType: "CURRENCY"}},
                    {id: "ga:CTR", attributes: {dataType: "PERCENT"}},
                    {id: "ga:sessionDuration", attributes: {dataType: "TIME"}},
                  ]
                end
              end
            end

            test "Convert Embulk data types" do
              conf = valid_config["in"]
              conf["dimensions"] = []
              conf["metrics"] = [
                "ga:sessionDuration",
                "ga:CPM",
                "ga:CTR",
                "ga:visits",
                "ga:itemsPerPurchase",
              ]
              expected_columns = [
                Column.new(nil, "date_hour", :timestamp),
                Column.new(nil, "session_duration", :double),
                Column.new(nil, "cpm", :double),
                Column.new(nil, "ctr", :double),
                Column.new(nil, "visits", :long),
                Column.new(nil, "items_per_purchase", :double),
                Column.new(nil, "view_id", :string),
              ]

              mock(Plugin).resume(anything, expected_columns, anything)
              Plugin.transaction(embulk_config(conf))
            end
          end
        end

        sub_test_case ".run" do
          sub_test_case "returned value should be added into page_builder" do
            setup do
              @page_builder = Object.new
              conf = valid_config["in"]
              conf["time_series"] = time_series
              @plugin = Plugin.new(embulk_config(conf), nil, nil, @page_builder)
            end

            sub_test_case "time_series: 'ga:dateHour'" do
              def time_series
                "ga:dateHour"
              end

              test "HH:00:00 time given" do
                Time.zone = "America/Los_Angeles"
                time = Time.zone.parse("2016-06-01 12:00:00").to_time
                any_instance_of(Client) do |klass|
                  stub(klass).each_report_row do |block|
                    row = {
                      "ga:dateHour" => time,
                      "ga:browser" => "wget",
                      "ga:visits" => 3,
                      "ga:pageviews" => 4,
                    }
                    block.call row
                  end
                end

                mock(@page_builder).add([time, "wget", 3, 4, nil]) # nil for view_id
                mock(@page_builder).finish
                @plugin.run
              end

              sub_test_case "last_record_time option" do
                setup do
                  stub(Plugin).calculate_next_times { {} }
                  Time.zone = "America/Los_Angeles"
                  @last_record_time = Time.zone.parse("2016-06-01 12:00:00").to_time

                  conf = valid_config["in"]
                  conf["time_series"] = time_series
                  conf["last_record_time"] = @last_record_time.strftime("%Y-%m-%d %H:%M:%S %z")
                  conf['incremental'] = true
                  @plugin = Plugin.new(embulk_config(conf), nil, nil, @page_builder)
                end

                test "ignore records when old" do
                  any_instance_of(Client) do |klass|
                    stub(klass).each_report_row do |block|
                      row = {
                        "ga:dateHour" => @last_record_time,
                        "ga:browser" => "wget",
                        "ga:visits" => 3,
                        "ga:pageviews" => 4,
                      }
                      block.call row
                    end
                    stub(klass).get_profile { {timezone: "America/Los_Angeles" } }
                  end

                  mock(@page_builder).add.never
                  mock(@page_builder).finish
                  @plugin.run
                end
              end

            end

            sub_test_case "time_series: 'ga:date'" do
              def time_series
                "ga:date"
              end

              test "00:00:00 time given" do
                Time.zone = "America/Los_Angeles"
                time = Time.zone.parse("2016-06-01 00:00:00").to_time
                any_instance_of(Client) do |klass|
                  stub(klass).each_report_row do |block|
                    row = {
                      "ga:date" => time,
                      "ga:browser" => "wget",
                      "ga:visits" => 3,
                      "ga:pageviews" => 4,
                    }
                    block.call row
                  end
                end

                mock(@page_builder).add([time, "wget", 3, 4, nil]) # nil for view_id
                mock(@page_builder).finish
                @plugin.run
              end

              sub_test_case "last_record_time option" do
                setup do
                  stub(Plugin).calculate_next_times { {} }
                  Time.zone = "America/Los_Angeles"
                  @last_record_time = Time.zone.parse("2016-06-01 12:00:00").to_time

                  conf = valid_config["in"]
                  conf["time_series"] = time_series
                  conf["last_record_time"] = @last_record_time.strftime("%Y-%m-%d %H:%M:%S %z")
                  conf['incremental'] = true

                  @plugin = Plugin.new(embulk_config(conf), nil, nil, @page_builder)
                end

                test "ignore records when old" do
                  any_instance_of(Client) do |klass|
                    stub(klass).each_report_row do |block|
                      row = {
                        "ga:date" => @last_record_time,
                        "ga:browser" => "wget",
                        "ga:visits" => 3,
                        "ga:pageviews" => 4,
                      }
                      block.call row
                    end
                    stub(klass).get_profile { {timezone: "America/Los_Angeles" } }
                  end

                  mock(@page_builder).add.never
                  mock(@page_builder).finish
                  @plugin.run
                end
              end
            end
          end
        end

        sub_test_case "run non-incremental" do
          sub_test_case " should be added to page_builder" do
            setup do
              Time.zone = "America/Los_Angeles"
              @last_record_time = Time.zone.parse("2016-06-01 12:00:00").to_time

              conf = valid_config["in"]
              conf["time_series"] = "ga:date"
              conf["last_record_time"] = @last_record_time.strftime("%Y-%m-%d %H:%M:%S %z")
              conf['incremental'] = false
              @plugin = Plugin.new(embulk_config(conf), nil, nil, @page_builder)
            end

            test "should allow record to be added to page_builder" do
              any_instance_of(Client) do |klass|
                stub(klass).each_report_row do |block|
                  row = {
                      "ga:date" => @last_record_time,
                      "ga:browser" => "wget",
                      "ga:visits" => 3,
                      "ga:pageviews" => 4,
                  }
                  block.call row
                end
              end

              mock(@page_builder).add(anything).at_least(1)
              mock(@page_builder).finish
              @plugin.run
            end
          end
        end

        sub_test_case "canonicalize_column_name" do
          data do
            [
              ["typical", ["ga:dateHour", "date_hour"]],
              ["all capital", ["ga:CPM", "cpm"]],
              ["capitals with word", ["ga:goalXXValue", "goal_xxvalue"]],
              ["ID", ["ga:adwordsCustomerID", "adwords_customer_id"]],
              ["word + capitals", ["ga:dcmCTR", "dcm_ctr"]],
            ]
          end
          test "converting" do |(target, expected)|
            assert_equal expected, Plugin.canonicalize_column_name(target)
          end
        end

        sub_test_case "calculate_next_times" do
          setup do
            @timeparser = ActiveSupport::TimeZone["UTC"]
            @page_builder = Object.new
            @config = embulk_config(valid_config["in"])
          end

          sub_test_case "ga:dateHour" do
            setup do
              conf = valid_config["in"]
              conf["time_series"] = "ga:dateHour"
              @config = embulk_config(conf)
            end

            sub_test_case "no records fetched" do
              data do
              [
                ["last_record_time is nil", [nil, nil]],
                ["last_record_time is empty", ["", nil]],
                ["last_record_time is blank", ["   ", nil]],
                ["last_record_time is valid", ["2019-01-01", "2019-01-01"]]
              ]
              end
              test "test calculate_next_times" do |(in_last_record_time, expected_last_record_time)|
                config["last_record_time"] = in_last_record_time
                expected = {
                  start_date: task["start_date"],
                  end_date: task["end_date"]
                }
                expected[:last_record_time] = expected_last_record_time unless expected_last_record_time.blank?
                plugin = Plugin.new(config, nil, nil, @page_builder)
                assert_equal expected, plugin.calculate_next_times(DEFAULT_TIMEZONE, nil)
              end
            end

            sub_test_case "updated" do
              sub_test_case "end_date is given as YYYY-MM-DD" do
                setup do
                  @config[:start_date] = "2000-01-01"
                  @config[:end_date] = "2000-01-05"
                end

                test "config_diff will modify" do
                  latest_time = parse_time("2000-01-07")
                  plugin = Plugin.new(config, nil, nil, @page_builder)
                  expected = {
                    start_date: "2000-01-06",
                    end_date: "today",
                    last_record_time: latest_time.strftime("%Y-%m-%d %H:%M:%S %z"),
                  }
                  assert_equal expected, plugin.calculate_next_times(DEFAULT_TIMEZONE, latest_time)
                end
              end
              sub_test_case "system timezone is 1 day behind profile timezone" do
                setup do
                  @config[:start_date] = "2000-01-01"
                  @config[:end_date] = "2000-01-05"
                  @timeparser = ActiveSupport::TimeZone["Asia/Ho_Chi_Minh"]
                end

                test "config_diff will modify with end date set to correct timezone" do
                  latest_time = parse_time("2000-01-07 00:00:00")
                  plugin = Plugin.new(config, nil, nil, @page_builder)
                  expected = {
                    start_date: "2000-01-06",
                    end_date: "today",
                    last_record_time: latest_time.strftime("%Y-%m-%d %H:%M:%S %z"),
                  }
                  assert_equal expected, plugin.calculate_next_times(DEFAULT_TIMEZONE, latest_time)
                end
              end

              sub_test_case "end_date is given as nDaysAgo" do
                setup do
                  @config[:start_date] = "2000-01-01"
                  @config[:end_date] = "10DaysAgo"
                end

                test "config_diff end_date won't modify" do
                  latest_time = parse_time("2000-01-07")
                  plugin = Plugin.new(config, nil, nil, @page_builder)
                  expected = {
                    start_date: "2000-01-06",
                    end_date: @config[:end_date],
                    last_record_time: latest_time.strftime("%Y-%m-%d %H:%M:%S %z"),
                  }
                  assert_equal expected, plugin.calculate_next_times(DEFAULT_TIMEZONE, latest_time)
                end
              end
            end
          end

          sub_test_case "ga:date" do
            setup do
              conf = valid_config["in"]
              conf["time_series"] = "ga:date"
              conf["last_record_time"] = "2019-01-01"
              @config = embulk_config(conf)
            end

            sub_test_case "no records fetched" do
              test "config_diff will keep previous" do
                plugin = Plugin.new(config, nil, nil, @page_builder)
                expected = {
                  start_date: task["start_date"],
                  end_date: task["end_date"],
                  last_record_time: task["last_record_time"],
                }
                assert_equal expected, plugin.calculate_next_times(DEFAULT_TIMEZONE, nil)
              end
            end

            sub_test_case "updated" do
              sub_test_case "end_date is given as YYYY-MM-DD" do
                setup do
                  @config[:start_date] = "2000-01-01"
                  @config[:end_date] = "2000-01-05"
                end

                test "config_diff will modify" do
                  latest_time = parse_time("2000-01-07")
                  plugin = Plugin.new(config, nil, nil, @page_builder)
                  expected = {
                    start_date: "2000-01-06",
                    end_date: "today",
                    last_record_time: latest_time.strftime("%Y-%m-%d %H:%M:%S %z"),
                  }
                  assert_equal expected, plugin.calculate_next_times(DEFAULT_TIMEZONE, latest_time)
                end

                test "config_diff will modify" do
                  latest_time = parse_time("2000-01-07")
                  plugin = Plugin.new(config, nil, nil, @page_builder)
                  expected = {
                    start_date: "2000-01-06",
                    end_date: "today",
                    last_record_time: latest_time.strftime("%Y-%m-%d %H:%M:%S %z"),
                  }
                  assert_equal expected, plugin.calculate_next_times(DEFAULT_TIMEZONE, latest_time)
                end

              end

              sub_test_case "end_date is nil" do
                setup do
                  @config[:start_date] = nil
                  @config[:end_date] = nil
                end

                test "config_diff will modify" do
                  latest_time = parse_time("2000-01-07")
                  plugin = Plugin.new(config, nil, nil, @page_builder)
                  expected = {
                    start_date: "2000-01-06",
                    end_date: "today",
                    last_record_time: latest_time.strftime("%Y-%m-%d %H:%M:%S %z"),
                  }
                  assert_equal expected, plugin.calculate_next_times(DEFAULT_TIMEZONE, latest_time)
                end
              end

              sub_test_case "end_date is given as nDaysAgo" do
                setup do
                  @config[:start_date] = "2000-01-01"
                  @config[:end_date] = "10DaysAgo"
                end

                test "config_diff end_date won't modify" do
                  latest_time = parse_time("2000-01-07")
                  plugin = Plugin.new(config, nil, nil, @page_builder)
                  expected = {
                    start_date: "2000-01-06",
                    end_date: @config[:end_date],
                    last_record_time: latest_time.strftime("%Y-%m-%d %H:%M:%S %z"),
                  }
                  assert_equal expected, plugin.calculate_next_times(DEFAULT_TIMEZONE, latest_time)
                end
              end
            end
          end

          def task
            Plugin.task_from_config(@config)
          end

          def config
            @config
          end

          def parse_time(time_string)
            @timeparser.parse(time_string)
          end

        end

        def valid_config
          fixture_load("valid.yml")
        end

        def embulk_config(hash)
          Embulk::DataSource.new(hash)
        end

        def valid_config_oauth
          fixture_load("valid_refresh_token.yml")
        end
      end
    end
  end
end
