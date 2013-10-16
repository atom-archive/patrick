child_process = require 'child_process'
fs = require 'fs'
path = require 'path'
parseUrl = require('url').parse

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

  mirror: (repoPath, snapshot, options, callback) ->
    if _.isFunction(options)
      callback = options
      options = {}

    {progressCallback} = options

    repo = git.open(repoPath)
    {branch, head, unpushedChanges, url, workingDirectoryChanges} = snapshot

    operations = []
    operationCount = 0
    if repo?
      unless urlsMatch(url, repo.getConfigValue('remote.origin.url'))
        callback(new Error("Repository already exists with different origin URL: #{repo.getWorkingDirectory()}"))
        return

      if not _.isEmpty(repo.getStatus()) and not isInSync(repo, snapshot)
        callback(new Error("Working directory is unclean: #{repo.getWorkingDirectory()}"))
        return

      operationCount++
      operations.push (args..., callback) ->
        command = "git fetch #{url}"
        progressCallback?('Fetching commits', command, operationCount)
        exec command, {cwd: repoPath}, (error) ->
          repo = git.open(repoPath) unless error?
          callback(error)
    else
      operationCount++
      operations.push (args..., callback) ->
        command = "git clone --recursive #{url} #{repoPath}"
        progressCallback?('Cloning repository', command, operationCount)
        exec command, (error) ->
          repo = git.open(repoPath) unless error?
          callback(error)

    if unpushedChanges
      operationCount++
      operations.push (args..., callback) -> tmp.file(callback)
      operations.push (bundleFile, args..., callback) ->
        fs.writeFile bundleFile, new Buffer(unpushedChanges, 'base64'), (error) ->
          callback(error, bundleFile)
      operations.push (bundleFile, callback) ->
        command = "git bundle unbundle #{bundleFile}"
        progressCallback?('Applying unpushed changes', command, operationCount)
        exec command, {cwd: repoPath}, callback

    operationCount++
    operations.push (args..., callback) ->
      if not repo?.getReferenceTarget("refs/heads/#{branch}")?
        command = "git checkout -b #{branch} #{head}"
        progressCallback?('Checking out branch', command, operationCount)
        exec command, {cwd: repoPath}, callback
      else if repo?.getAheadBehindCount(branch).ahead > 0
        i = 1
        loop
          newBranch = "#{branch}-#{i++}"
          break unless repo.getReferenceTarget("refs/heads/#{newBranch}")?

        command = "git checkout -b #{newBranch} #{head}"
        progressCallback?('Checking out branch', command, operationCount)
        exec command, {cwd: repoPath}, callback
      else
        operations = []
        operations.push (args..., callback) ->
          command = "git checkout #{branch}"
          progressCallback?('Checking out branch', command, operationCount)
          exec command, {cwd: repoPath}, callback

        operations.push (args..., callback) ->
          command = "git reset --hard #{head}"
          exec command, {cwd: repoPath}, callback

        async.waterfall operations, callback

    unless _.isEmpty(workingDirectoryChanges)
      operationCount++
      operations.push (args..., callback) ->
        progressCallback?('Applying working directory changes', null, operationCount)
        callback()

      for relativePath, contents of workingDirectoryChanges
        do (relativePath, contents) ->
          operations.push (args..., callback) ->
            filePath = path.join(repoPath, relativePath)
            if contents?
              fs.writeFile filePath, new Buffer(contents, 'base64'), callback
            else
              fs.unlink filePath, callback

    async.waterfall operations, callback

convertToUrl = (maybeUrl) ->
  {protocol, host} = parseUrl(maybeUrl)
  gitSshUrl = /([^@]+)@([^:]+):(.*)/
  if not protocol and not host and matches = maybeUrl.match(gitSshUrl)
    [all, user, host, path] = matches
    "git://#{user}@#{host}/#{path}"
  else
    maybeUrl

urlsMatch = (url1='', url2='') ->
  parsed1 = parseUrl(convertToUrl(url1))
  parsed2 = parseUrl(convertToUrl(url2))
  if parsed1.protocol is 'file:' and parsed2.protocol is 'file:'
    parsed1.pathname is parsed2.pathname
  else if parsed1.hostname and parsed1.hostname is parsed2.hostname
    path1 = parsed1.pathname?.replace(/\.git$/, '')
    path2 = parsed2.pathname?.replace(/\.git$/, '')
    path1 is path2
  else
    false

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

isInSync = (repo, snapshot) ->
  {branch, head, workingDirectoryChanges} = snapshot
  if repo.getShortHead() isnt branch
    false
  else if repo.getReferenceTarget(repo.getHead()) isnt head
    false
  else
    workingDirectoryChanges ?= {}
    repoChanges = repo.getStatus()
    workingDirectory = repo.getWorkingDirectory()
    for relativePath, status of repoChanges
      targetPath = path.join(workingDirectory, relativePath)
      sourceChange = workingDirectoryChanges[relativePath]
      if repo.isStatusDeleted(status)
        if fs.existsSync(targetPath) and sourceChange isnt null
          return false
      else if sourceChange is null
        return false
      else
        try
          if fs.readFileSync(targetPath, 'base64') isnt workingDirectoryChanges[relativePath]
            return false
        catch error
          return false

    true

exec = (args..., callback) ->
  child_process.exec args..., (error, stdout, stderr) ->
    if error
      error.stderr = stderr
      error.stdout = stdout
      error.command = args[0]
    callback(error, stdout, stderr)
