require 'uri'

module Embulk
  module Input
    module GoogleAnalytics
      class Plugin < InputPlugin
        ::Embulk::Plugin.register_input("google_analytics", self)
        AUTH_TYPE_JSON_KEY = 'json_key'.freeze
        AUTH_TYPE_REFRESH_TOKEN = 'refresh_token'.freeze

        # https://developers.google.com/analytics/devguides/reporting/core/dimsmets

        def self.transaction(config, &control)
          task = task_from_config(config)
          unless %w(ga:date ga:dateHour ga:yearMonth ga:year).include?(task["time_series"])
            raise ConfigError.new("Unknown time_series '#{task["time_series"]}'. Use 'ga:dateHour', 'ga:date', 'ga:year' or 'ga:yearMonth'")
          end

          raise ConfigError.new("Unknown Authentication method '#{task['auth_method']}'.") unless task['auth_method']

          if task['auth_method'] == Plugin::AUTH_TYPE_REFRESH_TOKEN
            unless task['client_id'] && task['client_secret'] && task['refresh_token']
              raise ConfigError.new("client_id, client_secret and refresh_token are required when using Oauth authentication")
            end
          elsif task['auth_method'] == Plugin::AUTH_TYPE_JSON_KEY
            if !valid_json?(task["json_key_content"])
              raise ConfigError.new("json_key_content is not a valid JSON object")
            end
          end

          columns_list = Client.new(task).get_columns_list

          columns = columns_from_task(task).map do |col_name|
            col_info = columns_list.find{|col| col[:id] == col_name} || {}
            # raise ConfigError.new("Unknown metric/dimension '#{col_name}'") unless col_info

            col_type =
              if col_info[:attributes]
                # standard dimension
                case col_info[:attributes][:dataType]
                when "STRING"
                  :string
                when "INTEGER"
                  :long
                when "PERCENT", "FLOAT", "CURRENCY", "TIME"
                  :double
                end
              else
                # custom dimension
                :string
              end

            # time_series column should be timestamp
            if col_name == task["time_series"]
              col_type = :timestamp
            end
            Column.new(nil, canonicalize_column_name(col_name), col_type)
          end

          columns << Column.new(nil, "view_id", :string)

          resume(task, columns, 1, &control)
        end

        def self.resume(task, columns, count, &control)
          task_reports = yield(task, columns, count)

          next_config_diff = task_reports.first
          return next_config_diff
        end

        def self.task_from_config(config)
          refresh_token = config.param('refresh_token', :string, default: nil)
          json_key_content = config.param("json_key_content", :string, default: nil)

          auth_method = Plugin::AUTH_TYPE_REFRESH_TOKEN if refresh_token
          auth_method = Plugin::AUTH_TYPE_JSON_KEY if json_key_content && auth_method == nil
            {
            "auth_method" => auth_method,
            "client_id" => config.param("client_id", :string, default: nil),
            "client_secret" => config.param("client_secret", :string, default: nil),
            "refresh_token" => refresh_token,
            "json_key_content" => json_key_content,
            "view_id" => config.param("view_id", :string),
            "dimensions" => config.param("dimensions", :array, default: []),
            "metrics" => config.param("metrics", :array, default: []),
            "metric_filters" => config.param("metric_filters", :array, default: []),
            "dimension_filters" => config.param("dimension_filters", :array, default: []),
            "segments" => config.param("segments", :array, default: []),
            "filters_expression" => config.param("filters_expression", :string, default: nil),
            "time_series" => config.param("time_series", :string),
            "start_date" => config.param("start_date", :string, default: nil),
            "end_date" => config.param("end_date", :string, default: nil),
            "incremental" => config.param("incremental", :bool, default: true),
            "last_record_time" => config.param("last_record_time", :string, default: nil),
            "retry_limit" => config.param("retry_limit", :integer, default: 5),
            "retry_initial_wait_sec" => config.param("retry_initial_wait_sec", :integer, default: 2),
            "sampling" => config.param("sampling", :string, default: "DEFAULT"),
          }
        end

        def self.columns_from_task(task)
          [
            task["time_series"],
            task["dimensions"],
            task["metrics"],
          ].flatten.uniq
        end

        def self.canonicalize_column_name(name)
          # ga:dateHour -> date_hour
          name.gsub(/^ga:/, "").gsub(/[A-Z]+/, "_\\0").gsub(/^_/, "").downcase
        end

        def self.guess(config)
          Embulk.logger.warn "Don't needed to guess for this plugin"
          return {}
        end

        def self.valid_json?(json_object)
          # 'null' string is a valid string for parse function
          # However in our case, json_content_key could not be 'null' therefore this check is added
          if json_object == "null"
              return false
          end
          begin
            JSON.parse(json_object)
                return true
          rescue JSON::ParserError => e
              return false
          end
        end

        def init
          if task["start_date"] && !task["end_date"]
            task["end_date"] = "today"
          end
        end

        def run
          client = Client.new(task, preview?)
          columns = self.class.columns_from_task(task) + ["view_id"]

          last_record_time = Time.parse(task["last_record_time"]) if task['incremental'] && !task["last_record_time"].blank?
          latest_time_series = nil
          skip_counter, total_counter = 0, 0
          client.each_report_row do |row|
            time = row[task["time_series"]]
            total_counter += 1
            if !preview? && last_record_time && time <= last_record_time
              skip_counter += 1
              next
            end

            values = row.values_at(*columns)
            page_builder.add values

            latest_time_series = [
              latest_time_series,
              time,
            ].compact.max
          end
          page_builder.finish

          Embulk.logger.info "Total: #{total_counter} rows."
          if skip_counter > 0
            Embulk.logger.info "#{skip_counter} rows were ignored because the rows' date is " +
                                   "before \"last_record_time\": #{last_record_time}."
          end

          if task["incremental"]
            calculate_next_times(client.get_profile[:timezone], latest_time_series)
          else
            {}
          end
        end

        def preview?
          org.embulk.spi.Exec.isPreview()
        rescue java.lang.NullPointerException
          false
        end

        def calculate_next_times(client_time_zone, fetched_latest_time)
          task_report = {}
          if fetched_latest_time
            # Convert fetched_last_time to user timezone
            timezone = ActiveSupport::TimeZone[client_time_zone]
            task_report[:start_date] = timezone.nil? ? fetched_latest_time.strftime("%Y-%m-%d") : timezone.parse(fetched_latest_time.to_s).strftime("%Y-%m-%d")

            # if end_date specified as statically YYYY-MM-DD, it will be conflict with start_date (end_date < start_date)
            # Or when end_date is nil, only start_date will be filled on next run but it is illegal API request.
            # Modify end_date as "today" to be safe
            if task["end_date"].nil? || task["end_date"].match(/[0-9]{4}-[0-9]{2}-[0-9]{2}/)
              task_report[:end_date] = "today" # "today" means now. running at 03:30 AM, will got 3 o'clock data.
            else
              task_report[:end_date] = task["end_date"]
            end

            # "start_date" format is YYYY-MM-DD, but ga:dateHour will return records by hourly.
            # If run at 2016-07-03 05:00:00, start_date will set "2016-07-03" and got records until 2016-07-03 05:00:00.
            # Then next run at 2016-07-04 05:00, will got records between 2016-07-03 00:00:00 and 2016-07-04 05:00:00.
            # It will evantually duplicated between 2016-07-03 00:00:00 and 2016-07-03 05:00:00
            #
            #           Date|        2016-07-03      |   2016-07-04
            #           Hour|    5                   |    5
            # 1st run ------|----|                   |
            # 2nd run       |------------------------|-----
            #               ^^^^^ duplicated
            #
            # "last_record_time" option solves that problem
            #
            #           Date|        2016-07-03      |   2016-07-04
            #           Hour|    5                   |    5
            # 1st run ------|----|                   |
            # 2nd run       #####|-------------------|-----
            #               ^^^^^ ignored (skipped)
            #
            task_report[:last_record_time] = fetched_latest_time.strftime("%Y-%m-%d %H:%M:%S %z")
          else
            # no records fetched, don't modify config_diff
            task_report = {
              start_date: task["start_date"],
              end_date: task["end_date"]
            }
            # write last_record_time only when last_record_time is not nil and not empty
            unless task["last_record_time"].blank?
              task_report[:last_record_time] = task["last_record_time"]
            end 
          end
          task_report
        end
      end
    end
  end
end
