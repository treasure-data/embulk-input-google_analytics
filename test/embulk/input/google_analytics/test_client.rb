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
