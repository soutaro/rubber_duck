require 'pathname'

require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/*_test.rb']
  t.verbose = true
end

Rake::Task[:test].enhance(["test:setup"])

namespace :test do
  desc "Setup for test"
  task :setup do
    test_dir = Pathname(__dir__) + "test/data"

    tmp_dir = Pathname(__dir__) + "tmp/data"
    tmp_dir.mkpath

    test_dir.children.each do |path|
      if path.extname == ".rb"
        db_path = tmp_dir + "#{path.basename.to_s}.json"

        if !db_path.file? || path.mtime > db_path.mtime
          sh({ "DEFSDB_DATABASE_NAME" => db_path.to_s }, "ruby", "-rbundler/setup", "-rdefsdb/autorun", path.to_s)
        end
      end
    end
  end
end
