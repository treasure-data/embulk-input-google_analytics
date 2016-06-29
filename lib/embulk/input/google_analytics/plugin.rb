module Embulk
  module Input
    module GoogleAnalytics
      class Plugin < InputPlugin
        ::Embulk::Plugin.register_input("google_analytics", self)

        # https://developers.google.com/analytics/devguides/reporting/core/dimsmets

        def self.transaction(config, &control)
          task = task_from_config(config)
          unless %w(ga:date ga:dateHour).include?(task["time_series"])
            raise ConfigError.new("Unknown time_series '#{task["time_series"]}'. Use 'ga:dateHour' or 'ga:date'")
          end
          columns_list = Client.new(task).get_columns_list

          columns = columns_from_task(task).map do |col_name|
            col_info = columns_list.find{|col| col[:id] == col_name}
            raise ConfigError.new("Unknown metric/dimension '#{col_name}'") unless col_info

            col_type = 
              case col_info[:attributes][:dataType]
              when "STRING"
                :string
              when "INTEGER", "CURRENCY"
                :long
              when "PERCENT", "FLOAT"
                :float
              when "TIME"
                :timestamp
              end

            # time_series column should be timestamp
            if col_name == task["time_series"]
              col_type = :timestamp
            end
            Column.new(nil, canonicalize_column_name(col_name), col_type)
          end

          resume(task, columns, 1, &control)
        end

        def self.resume(task, columns, count, &control)
          task_reports = yield(task, columns, count)

          next_config_diff = {}
          return next_config_diff
        end

        # TODO
        #def self.guess(config)
        #  sample_records = [
        #    {"example"=>"a", "column"=>1, "value"=>0.1},
        #    {"example"=>"a", "column"=>2, "value"=>0.2},
        #  ]
        #  columns = Guess::SchemaGuess.from_hash_records(sample_records)
        #  return {"columns" => columns}
        #end

        def self.task_from_config(config)
          json_keyfile = config.param("json_keyfile", :hash, default: {content: ""}).param("content", :string)
          {
            "json_keyfile" => json_keyfile,
            "view_id" => config.param("view_id", :string),
            "dimensions" => config.param("dimensions", :array, default: []),
            "metrics" => config.param("metrics", :array, default: []),
            "time_series" => config.param("time_series", :string),
            "start_date" => config.param("start_date", :string, default: nil),
            "end_date" => config.param("end_date", :string, default: nil),
          }
        end

        def self.columns_from_task(task)
          columns = [
            task["time_series"],
            task["dimensions"],
            task["metrics"],
          ].flatten.uniq
        end

        def self.canonicalize_column_name(name)
          # ga:dateHour -> date_hour
          name.gsub(/^ga:/, "").gsub(/[A-Z]/, "_\\0").gsub(/^_/, "").downcase
        end

        def init
        end

        def run
          client = Client.new(task, preview?)
          columns = self.class.columns_from_task(task)
          date_format =
            case task["time_series"]
            when "ga:dateHour"
              "%Y%m%d%H %z"
            when "ga:date"
              "%Y%m%d %z"
            end

          client.each_report_row do |row|
            values = row.values_at(*columns)
            # Always values[0] is a time_series column
            values[0] = Time.strptime(values.first, date_format)
            page_builder.add values
          end
          page_builder.finish

          task_report = {}
          return task_report
        end

        def preview?
          org.embulk.spi.Exec.isPreview()
        rescue java.lang.NullPointerException => e
          false
        end

      end
    end
  end
end
