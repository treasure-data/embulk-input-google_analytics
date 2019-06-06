require "perfect_retry"
require "active_support/core_ext/time"
require "google/apis/analyticsreporting_v4"
require "google/apis/analytics_v3"

# Avoid such error:
# PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
Google::Apis::ClientOptions.default.use_net_http = true

module Embulk
  module Input
    module GoogleAnalytics
      class Client
        attr_reader :task

        def initialize(task, is_preview = false)
          @task = task
          @is_preview = is_preview
        end

        def preview?
          @is_preview
        end

        def each_report_row(&block)
          page_token = nil
          Embulk.logger.info "view_id:#{view_id} timezone has been set as '#{get_profile[:timezone]}'"

          loop do
            result = get_reports(page_token)
            report = result.to_h[:reports].first

            if !report[:data].has_key?(:rows)
              Embulk.logger.warn "Result doesn't contain rows: #{result.to_h}"
              break
            end

            if report[:data][:rows].empty?
              Embulk.logger.warn "Result has 0 rows."
              break
            end

            dimensions = report[:column_header][:dimensions]
            metrics = report[:column_header][:metric_header][:metric_header_entries].map{|m| m[:name]}
            report[:data][:rows].each do |row|
              dim = dimensions.zip(row[:dimensions]).to_h
              met = metrics.zip(row[:metrics].first[:values]).to_h
              format_row = dim.merge(met)
              raw_time = format_row[task["time_series"]]
              optimize_value_by_query_limit?(raw_time)
              next if too_early_data?(raw_time)
              format_row[task["time_series"]] = time_parse_with_profile_timezone(raw_time)
              format_row["view_id"] = view_id
              block.call format_row
            end

            break if preview?

            unless page_token = report[:next_page_token]
              break
            end
            Embulk.logger.info "Fetching report with page_token: #{page_token}"
          end
        end

        def get_profile
          @profile ||=
            begin
              profile = get_all_profiles.to_h[:items].find do |prof|
                prof[:id] == view_id
              end

              unless profile
                raise Embulk::ConfigError.new("Can't find view_id:#{view_id} profile via Google Analytics API.")
              end

              profile
            end
        end

        def get_all_profiles
          service = Google::Apis::AnalyticsV3::AnalyticsService.new
          service.authorization = auth

          Embulk.logger.debug "Fetching profile from API"
          retryer.with_retry do
            service.list_profiles("~all", "~all")
          end
        end

        def optimize_value_by_query_limit?(data)
          # For any date range, Analytics returns a maximum of 1 million rows for the report. Rows in excess of 1 million are rolled-up into an (other) row.
          # See more details: https://support.google.com/analytics/answer/1009671
          if data.to_s == "(other)"
            raise Embulk::DataError.new('Stop fetching data from Analytics because over 1M data fetching was limited. Please reduce data range to fetch data according to this article: https://support.google.com/analytics/answer/1009671.')
          end
        end

        def time_parse_with_profile_timezone(time_string)
          date_format =
            case task["time_series"]
            when "ga:dateHour"
              "%Y%m%d%H"
            when "ga:date"
              "%Y%m%d"
            when "ga:yearMonth"
              "%Y%m"
            when "ga:year"
              "%Y"
            end
          parts = Date._strptime(time_string, date_format)
          unless parts
            # strptime was failed. Google API returns unexpected date string.
            raise Embulk::DataError.new("Failed to parse #{task["time_series"]} data. The value is '#{time_string}'(#{time_string.class}) and it doesn't match with '#{date_format}'.")
          end

          swap_time_zone do
            case task["time_series"]
            when "ga:year", "ga:yearMonth"
              [parts[:year], parts[:mon]].compact.map(&:to_s).join('-')
            else
              Time.zone.local(*parts.values_at(:year, :mon, :mday, :hour)).to_time
            end
          end
        end

        def get_reports(page_token = nil)
          # https://developers.google.com/analytics/devguides/reporting/core/v4/rest/v4/reports/batchGet
          service = Google::Apis::AnalyticsreportingV4::AnalyticsReportingService.new
          service.authorization = auth

          request = Google::Apis::AnalyticsreportingV4::GetReportsRequest.new
          request.report_requests = build_report_request(page_token)

          Embulk.logger.info "Query to Core Report API: #{request.to_json}"
          retryer.with_retry do
            service.batch_get_reports request
          end
        end

        def get_columns_list
          columns = get_custom_dimensions + get_metadata_columns
          canonical_column_names(columns)
        end

        def canonical_column_names(columns)
          result = []
          columns.each do |col|
            if col[:id].match(/XX/)
              # for such columns:
              # https://developers.google.com/analytics/devguides/reporting/core/dimsmets#view=detail&group=content_grouping
              # https://developers.google.com/analytics/devguides/reporting/metadata/v3/devguide#attributes
              min = [
                col[:attributes][:minTemplateIndex],
                col[:attributes][:premiumMinTemplateIndex],
              ].compact.min
              max = [
                col[:attributes][:maxTemplateIndex],
                col[:attributes][:premiumMaxTemplateIndex],
              ].compact.max

              min.upto(max) do |n|
                actual_id = col[:id].gsub(/XX/, n.to_s)
                result << col.merge(id: actual_id)
              end
            else
              result << col
            end
          end
          result
        end

        def get_metadata_columns
          # https://developers.google.com/analytics/devguides/reporting/metadata/v3/reference/metadata/columns/list
          service = Google::Apis::AnalyticsV3::AnalyticsService.new
          service.authorization = auth
          retryer.with_retry do
            service.list_metadata_columns("ga").to_h[:items]
          end
        end

        def get_custom_dimensions
          # https://developers.google.com/analytics/devguides/config/mgmt/v3/mgmtReference/management/customDimensions/list
          service = Google::Apis::AnalyticsV3::AnalyticsService.new
          service.authorization = auth
          retryer.with_retry do
            service.list_custom_dimensions(get_profile[:account_id], get_profile[:web_property_id]).to_h[:items]
          end
        end

        def build_report_request(page_token = nil)
          query = {
            view_id: view_id,
            dimensions: [{name: task["time_series"]}] + task["dimensions"].map{|d| {name: d}},
            metrics: task["metrics"].map{|m| {expression: m}},
            include_empty_rows: true,
            page_size: preview? ? 10 : 10000,
            metric_filter_clauses: [{ filters: deeply_symbolyze_keys(task["metric_filters"]) }],
            dimension_filter_clauses: [{ filters: deeply_symbolyze_keys(task["dimension_filters"]) }],
            segments: deeply_symbolyze_keys(task["segments"]),
            filters_expression: task["filters_expression"],
            sampling_level: task["sampling"],
          }

          if task["start_date"] || task["end_date"]
            query[:date_ranges] = [{
              start_date: task["start_date"],
              end_date: task["end_date"],
            }]
          end

          if page_token
            query[:page_token] = page_token
          end

          [query]
        end

        def deeply_symbolyze_keys(val)
          case val
          when Array
            val.map{|v| deeply_symbolyze_keys(v) }
          when Hash
            val.map{|k,v| [k.to_sym, deeply_symbolyze_keys(v)]}.to_h
          else
            val
          end
        end

        def view_id
          task["view_id"]
        end

        def auth
          retryer.with_retry do
            case task['auth_method']
            when Plugin::AUTH_TYPE_JSON_KEY
              Google::Auth::ServiceAccountCredentials.make_creds(
                json_key_io: StringIO.new(task["json_key_content"]),
                scope: "https://www.googleapis.com/auth/analytics.readonly"
              )
            when Plugin::AUTH_TYPE_REFRESH_TOKEN
              Google::Auth::UserRefreshCredentials.new(
                'token_credential_uri': Google::Auth::UserRefreshCredentials::TOKEN_CRED_URI,
                'client_id': task['client_id'],
                'client_secret': task['client_secret'],
                'refresh_token': task['refresh_token']
              )
            else
              raise Embulk::ConfigError.new("Unknown Authentication method: '#{task['auth_method']}'.")
            end
          end
        rescue Google::Apis::AuthorizationError => e
          raise ConfigError.new(e.message)
        end

        def swap_time_zone(&block)
          orig_timezone = Time.zone
          Time.zone = get_profile[:timezone]
          yield
        ensure
          Time.zone = orig_timezone
        end

        def too_early_data?(time_str)
          # fetching 20160720 data on 2016-07-20, it is too early fetching
          swap_time_zone do
            now = Time.zone.now
            case task["time_series"]
            when "ga:dateHour"
              time_str.to_i >= now.strftime("%Y%m%d%H").to_i
            when "ga:date"
              time_str.to_i >= now.strftime("%Y%m%d").to_i
            when "ga:yearMonth"
              time_str.to_i >= now.strftime("%Y%m").to_i
            when "ga:year"
              time_str.to_i >= now.strftime("%Y").to_i
            end
          end
        end

        def retryer
          PerfectRetry.new do |config|
            config.limit = task["retry_limit"]
            config.logger = Embulk.logger
            config.log_level = nil

            # https://developers.google.com/analytics/devguides/reporting/core/v4/errors
            # https://developers.google.com/analytics/devguides/reporting/core/v4/limits-quotas#additional_quota
            # https://github.com/google/google-api-ruby-client/blob/master/lib/google/apis/errors.rb
            # https://github.com/google/google-api-ruby-client/blob/0.9.11/lib/google/apis/core/http_command.rb#L33
            config.rescues = Google::Apis::Core::HttpCommand::RETRIABLE_ERRORS
            config.dont_rescues = [Embulk::DataError, Embulk::ConfigError]
            config.sleep = lambda{|n| task["retry_initial_wait_sec"]* (2 ** (n-1)) }
            config.raise_original_error = true
          end
        end
      end
    end
  end
end
