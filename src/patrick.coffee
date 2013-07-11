child_process = require 'child_process'
fs = require 'fs'
path = require 'path'

_ = require 'underscore'
async = require 'async'
git = require 'git-utils'
tmp = require 'tmp'

module.exports =
  snapshot: (repoPath, callback) ->
    repo = git.open(repoPath)
    snapshot =
      branch: repo.getShortHead()
      head: repo.getReferenceTarget(repo.getHead())
      url: repo.getConfigValue('remote.origin.url')

    operations = []
    if repo.getAheadBehindCount().ahead > 0
      operations.push (callback) ->
        bundleUnpushedChanges repo, (error, bundleFile) ->
          unless error?
            snapshot.unpushedChanges = fs.readFileSync(bundleFile, 'base64')
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
    {branch, head, unpushedChanges, url, workingDirectoryChanges} = snapshot

    operations = []
    if repo?
      operations.push (args..., callback) ->
        command = "git fetch #{url}"
        exec command, {cwd: repoPath}, (error) ->
          repo = git.open(repoPath) unless error?
          callback(error)
    else
      operations.push (args..., callback) ->
        command = "git clone --recursive #{url} #{repoPath}"
        exec command, {cwd: repoPath}, (error) ->
          repo = git.open(repoPath) unless error?
          callback(error)

    if unpushedChanges
      operations.push (args..., callback) -> tmp.file(callback)
      operations.push (bundleFile, args..., callback) ->
        fs.writeFile bundleFile, new Buffer(unpushedChanges, 'base64'), (error) ->
          callback(error, bundleFile)
      operations.push (bundleFile, callback) ->
        command = "git bundle unbundle #{bundleFile}"
        exec command, {cwd: repoPath}, callback

    operations.push (args..., callback) ->
      command = "git checkout #{branch}"
      exec command, {cwd: repoPath}, callback

    operations.push (args..., callback) ->
      command = "git reset --hard #{head}"
      exec command, {cwd: repoPath}, callback

    for relativePath, contents of workingDirectoryChanges ? {}
      do (relativePath, contents) ->
        operations.push (args..., callback) ->
          filePath = path.join(repoPath, relativePath)
          if contents?
            fs.writeFile filePath, new Buffer(contents, 'base64'), callback
          else
            fs.unlink filePath, callback

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
  workingDirectory = repo.getWorkingDirectory()
  for relativePath, pathStatus of repo.getStatus()
    do (relativePath, pathStatus) ->
      operations.push (callback) ->
        if repo.isStatusDeleted(pathStatus)
          workingDirectoryChanges[relativePath] = null
          callback()
        else
          fs.readFile path.join(workingDirectory, relativePath), 'base64', (error, buffer) ->
            workingDirectoryChanges[relativePath] = buffer.toString() if buffer?
            callback(error)

  async.waterfall operations, (error) -> callback(error, workingDirectoryChanges)

exec = (args..., callback) ->
  child_process.exec args..., (error, stdout, stderr) ->
    if error
      error.stderr = stderr
      error.stdout = stdout
      error.command = args[0]
    callback(error, stdout, stderr)
