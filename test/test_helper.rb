require 'pathname'
require 'bundler/setup'

$LOAD_PATH << (Pathname(__dir__).parent + "lib").to_s

require 'rubber_duck'
require 'minitest/autorun'

module TestHelper
  DB_CACHE = {}

  def analyzer(script)
    script_path = Pathname(__dir__) + "data" + script
    ast = Parser::CurrentRuby.parse(script_path.read, script_path.to_s)
    RubberDuck::Analyzer.new(database(script), [ast])
  end

  def data_script_path(script)
    Pathname(__dir__) + "data" + script
  end

  def database(script)
    DB_CACHE[script] ||= Defsdb::Database.open(Pathname(__dir__).parent + "tmp/data" + "#{script}.json")
  end
end
