desc "aws-record unit tests"
RSpec::Core::RakeTask.new('test:unit') do |t|
  t.rspec_opts = "-I #{$REPO_ROOT}/lib"
  t.rspec_opts << " -I #{$REPO_ROOT}/spec"
  t.pattern = "#{$REPO_ROOT}/spec"
end

desc 'aws-record integration tests'
task 'test:integration' do |t|
  if ENV['AWS_INTEGRATION']
    exec("bundle exec cucumber -t ~@veryslow")
  else
    puts(<<-MSG)

*** skipping aws-record integration tests ***
  export AWS_INTEGRATION=1 to enable integration tests

    MSG
  end
end
