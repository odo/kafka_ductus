#compdef krepl

local -a _1st_arguments
_1st_arguments=(
  'start:start the replicator as a daemon'
  'console:start the replicator in a shell'
  'attach:attach a shell to a running replicator'
  'stop:stop the replicator'
  'running:determine if the replicator is running'
  'status:get status for all topics'
  'zero_offsets:set offsets to zero'
  'reset_offsets:reset offsets to newest value (head)'
  'reset_to_oldest_offsets:reset offsets to oldest value'
  'reset_offsets_from_file:reset offsets from a json file'
)

_arguments \
  '*:: :->subcmds' && return 0

if (( CURRENT == 1 )); then
  _describe -t commands "redis-cli subcommand" _1st_arguments
  return
fi
