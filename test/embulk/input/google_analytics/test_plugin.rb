require "embulk"
Embulk.setup

require "embulk/input/google_analytics"
require "override_assert_raise"
require "fixture_helper"

module Embulk
  module Input
    module GoogleAnalytics
      class TestPlugin < Test::Unit::TestCase
        include OverrideAssertRaise
        include FixtureHelper

        sub_test_case ".transaction" do
          setup { stub(Plugin).resume { Hash.new } }
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

            def unknown_col_name
              "ga:foooooo"
            end

            def expected_message
              "Unknown metric/dimension '#{unknown_col_name}'"
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

                mock(@page_builder).add([time, "wget", 3, 4])
                mock(@page_builder).finish
                @plugin.run
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

                mock(@page_builder).add([time, "wget", 3, 4])
                mock(@page_builder).finish
                @plugin.run
              end
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
