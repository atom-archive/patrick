{exec} = require 'child_process'
fs = require 'fs'

async = require 'async'
git = require 'git-utils'
tmp = require 'tmp'

module.exports =
  snapshot: (repoPath, callback) ->
    repo = git.open(repoPath)
    snapshot = {}

    if repo.getAheadBehindCount().ahead > 0
      bundleUnpushedChanges repo, (error, bundleFile) ->
        unless error?
          snapshot.unpushedChanges = fs.readFileSync(bundleFile, 'base64')
          snapshot.head = repo.getReferenceTarget(repo.getHead())
          snapshot.branch = repo.getShortHead()
        callback(error, snapshot)

  mirror: (repoPath, snapshot, callback) ->
    repo = git.open(repoPath)
    {unpushedChanges, head, branch} = snapshot

    if unpushedChanges
      operations = []
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
      async.waterfall operations, callback

bundleUnpushedChanges = (repo, callback) ->
  localBranch = repo.getShortHead()
  upstreamBranch = repo.getUpstreamBranch()

  tmp.file (error, bundleFile) ->
    command = "git bundle create #{bundleFile} #{upstreamBranch}..#{localBranch}"
    exec command, {cwd: repo.getWorkingDirectory()}, (error, stdout, stderr) ->
      callback(error, bundleFile)
