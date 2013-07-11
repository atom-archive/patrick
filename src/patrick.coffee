{exec} = require 'child_process'
fs = require 'fs'
path = require 'path'

_ = require 'underscore'
async = require 'async'
git = require 'git-utils'
tmp = require 'tmp'

module.exports =
  snapshot: (repoPath, callback) ->
    repo = git.open(repoPath)
    snapshot = {}

    operations = []
    if repo.getAheadBehindCount().ahead > 0
      operations.push (callback) ->
        bundleUnpushedChanges repo, (error, bundleFile) ->
          unless error?
            snapshot.unpushedChanges = fs.readFileSync(bundleFile, 'base64')
            snapshot.head = repo.getReferenceTarget(repo.getHead())
            snapshot.branch = repo.getShortHead()
          callback(error)

    unless _.isEmpty(repo.getStatus())
      operations.push (callback) ->
        getWorkingDirectoryChanges repo, (error, workingDirectoryChanges) ->
          unless error?
            snapshot.workingDirectoryChanges = workingDirectoryChanges
          callback(error)

    async.waterfall operations, (error) -> callback(error, snapshot)

  mirror: (repoPath, snapshot, callback) ->
    repo = git.open(repoPath)
    {branch, head, unpushedChanges, workingDirectoryChanges} = snapshot

    operations = []
    if unpushedChanges
      operations.push (callback) -> tmp.file(callback)
      operations.push (bundleFile, args..., callback) ->
        fs.writeFile bundleFile, new Buffer(unpushedChanges, 'base64'), (error) ->
          callback(error, bundleFile)
      operations.push (bundleFile, callback) ->
        command = "git bundle unbundle #{bundleFile}"
        exec command, {cwd: repoPath}, callback
      operations.push (args..., callback) ->
        command = "git checkout #{branch} && git reset --hard #{head}"
        exec command, {cwd: repoPath}, callback

    for relativePath, contents of workingDirectoryChanges ? {}
      do (relativePath, contents) ->
        operations.push (args..., callback) ->
          filePath = path.join(repoPath, relativePath)
          fs.writeFile filePath, new Buffer(contents, 'base64'), callback

    async.waterfall operations, callback

bundleUnpushedChanges = (repo, callback) ->
  localBranch = repo.getShortHead()
  upstreamBranch = repo.getUpstreamBranch()

  tmp.file (error, bundleFile) ->
    command = "git bundle create #{bundleFile} #{upstreamBranch}..#{localBranch}"
    exec command, {cwd: repo.getWorkingDirectory()}, (error, stdout, stderr) ->
      callback(error, bundleFile)

getWorkingDirectoryChanges = (repo, callback) ->
  operations = []
  workingDirectoryChanges = {}
  _.keys(repo.getStatus()).forEach (relativePath) ->
    operations.push (callback) ->
      fs.readFile path.join(repo.getWorkingDirectory(), relativePath), 'base64', (error, buffer) ->
        workingDirectoryChanges[relativePath] = buffer.toString() if buffer?
        callback(error)

  async.waterfall operations, (error) -> callback(error, workingDirectoryChanges)
