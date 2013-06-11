logging = require("./logging")

VERSION = "0.8.0-20130611"

# put all runtime config stuff in here, so it can be accessed from a running
# build script too.
Config =
  useColors: logging.useColors
  logVerbose: logging.setVerbose
  logDebug: logging.setDebug

  cwd: (folder) ->
    if folder? then process.chdir(folder)
    process.cwd()

  rulesFile: (filename) ->
    if filename? then @_rulesFile = filename
    @_rulesFile

  version: ->
    VERSION


exports.Config = Config
exports.VERSION = VERSION
