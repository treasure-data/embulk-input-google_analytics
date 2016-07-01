require "yaml"
require "pathname"

module FixtureHelper
  def fixture_dir
    Pathname.new(__FILE__).dirname.join("fixtures")
  end

  def fixture_read(name)
    fixture_dir.join(name).read
  end

  def fixture_load(name)
    YAML.load fixture_read(name)
  end
end
