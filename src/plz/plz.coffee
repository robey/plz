fs = require 'fs'
nopt = require 'nopt'
path = require 'path'
Q = require 'q'
sprintf = require 'sprintf'
util = require 'util'
vm = require 'vm'

Config = require("./config").Config
context = require("./context")
logging = require("./logging")
rulesfile = require("./rulesfile")
statefile = require("./statefile")
task = require("./task")
task_table = require("./task_table")

DEFAULT_TASK = "build"
SETTING_RE = /^(\w[-\.\w]*)=(.*)$/

longOptions =
  filename: [ path, null ]
  folder: [ path, null ]
  watch: Boolean
  version: Boolean
  help: Boolean
  tasks: Boolean
  verbose: Boolean
  debug: Boolean
  "no-colors": Boolean
  colors: Boolean

shortOptions =
  f: [ "--filename" ]
  w: [ "--watch" ]
  F: [ "--folder" ]
  v: [ "--verbose" ]
  D: [ "--debug" ]

main = ->
  settings = {}
  readRcFile(settings)
  .then (settings) ->
    # allow settings.options to take effect, then allow argv to override them.
    if settings.options? then parseOptions(settings.options.split(" "), 0)
    options = parseOptions(process.argv)
    run(options, settings)
  .fail (error) ->
    logging.error error.message
    logging.info error.stack
    process.exit 1

parseOptions = (argv, slice) ->
  options = nopt(longOptions, shortOptions, argv, slice)
  if options.colors then logging.useColors(true)
  if options["no-colors"] then logging.useColors(false)
  if options.verbose then logging.setVerbose(true)
  if options.debug then logging.setDebug(true)
  if options.folder then process.chdir(options.folder)
  if options.version
    console.log "plz #{Config.version()}"
    process.exit 0
  if options.help
    console.log(HELP)
  options

displayHelp = (table) ->
  taskNames = table.getNames()
  if taskNames.length == 0
    console.log "No tasks defined."
  else
    width = taskNames.map((x) -> x.length).reduce((a, b) -> Math.max(a, b))
    console.log "Known tasks:"
    for t in taskNames
      console.log sprintf.sprintf("  %#{width}s - %s", t, table.getTask(t).description)
    console.log ""
  process.exit 0

run = (options, overlaySettings) ->
  startTime = Date.now()
  settings = {}
  rulesfile.loadRules(options, settings).then (table) ->
    recursiveMerge settings, overlaySettings
    runWithTable(options, settings, table, startTime)

recursiveMerge = (obj1, obj2) ->
  for k, v of obj2
    if typeof v == "object"
      obj1[k] or= {}
      recursiveMerge(obj1[k], v)
    else
      obj1[k] = v

runWithTable = (options, settings, table, startTime) ->
  table.validate()
  table.consolidate()
  if options.help or options.tasks then displayHelp(table)
  options.table = table
  parseTaskList(options, settings)
  logging.debug "Settings: #{util.inspect(settings)}"
  for name in options.tasklist
    if not table.getTask(name)? then throw new Error("No task named '#{name}'")
  statefile.loadState()
  .then (state) ->
    if (not state?.version?) or (state.version > 1) then state = { snapshots: { } }
    table.enqueueAlways()
    for [ name, filenames ] in (state.incomplete or []) then if table.getTask(name)? then table.runner.enqueue(name, filenames)
    for name in options.tasklist then table.runner.enqueue(name)
    logging.debug "Activating watches..."
    table.activate(state.snapshots, persistent: options.watch, interval: 250)
  .then ->
    table.runner.start()
    table.runQueue()
  .then ->
    if options.watch
      logging.taskinfo "Watching for changes..."
    else
      duration = Date.now() - startTime
      if duration <= 2000
        humanTime = "#{duration} milliseconds"
      else if duration <= 120000
        humanTime = sprintf.sprintf("%.1f seconds", duration / 1000.0)
      else
        humanTime = "#{Math.floor(duration / 60000.0)} minutes"
      logging.taskinfo "plz: finished in #{humanTime}."

readRcFile = (settings) ->
  filename = if process.env["PLZRC"]?
    process.env["PLZRC"]
  else
    user_home = process.env["HOME"] or process.env["USERPROFILE"]
    "#{user_home}/.plzrc"
  if fs.existsSync(filename)
    deferred = Q.defer()
    fs.readFile filename, (error, data) ->
      if error?
        deferred.reject(error)
      else
        for line in data.toString().split("\n")
          line = line.trim()
          if line.match /^\#/
            # ignore
          else if (m = line.match SETTING_RE)
            settings[m[1]] = m[2]
        deferred.resolve(settings)
    deferred.promise
  else
    Q(settings)

parseTaskList = (options, settings={}) ->
  tasklist = []
  for word in options.argv.remain
    if word.match task.TASK_REGEX
      tasklist.push word
    else if (m = word.match SETTING_RE)
      segments = m[1].split(".")
      obj = settings
      for segment in segments[0...-1]
        obj = (obj[segment] or= {})
      obj[segments[segments.length - 1]] = m[2]
    else
      throw new Error("I don't know what to do with '#{word}'")
  options.tasklist = tasklist
  [ tasklist, settings ]


HELP = """
plz #{Config.version()}
usage: plz [options] [task-setting]* [task-name]*

general options are listed below. task-settings are all of the form
"<name>=<value>".

example:
  plz -f #{rulesfile.DEFAULT_FILENAME} build debug=true run

  loads rules from #{rulesfile.DEFAULT_FILENAME}, adds { debug: "true" } to the
  global settings object, then runs task "build" followed by task "run".

options:
  --filename FILENAME (-f)
      use a specific rules file (default: #{Config.rulesFile()})
  --tasks
      show the list of tasks and their descriptions
  --watch (-w)
      keep running (until killed), watching for changed files
  --folder FOLDER (-F)
      move into a folder before running
  --help
      this help
  --version
      show the version string and exit
  --verbose (-v)
      log more about what it's doing
  --debug (-D)
      log quite a lot more about what it's thinking
  --colors / --no-colors
      override the color detection to turn on/off terminal colors

"""

exports.main = main
exports.run = run
exports.parseTaskList = parseTaskList
exports.readRcFile = readRcFile
