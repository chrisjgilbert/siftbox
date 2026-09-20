# Sets environment variables for the length of a block and puts them back
# afterwards, whatever the block does.
#
# ENV is process-wide and the suite is one process, so a variable an example
# sets and fails to restore decides what every example after it sees — a
# reader seeded into the wrong database, a key present where the example
# wanted it absent. Four specs each carried their own copy of this, which was
# four ensure blocks to get wrong; this is the one of them.
#
# Assigning nil deletes the variable, which is both how an example asks for
# one to be absent and how a variable that was absent to begin with is put
# back.
module EnvironmentHelper
  def with_environment(values)
    originals = values.keys.index_with { |name| ENV[name] }
    values.each { |name, value| ENV[name] = value }

    yield
  ensure
    originals.each { |name, value| ENV[name] = value }
  end
end

RSpec.configure do |config|
  config.include EnvironmentHelper
end
