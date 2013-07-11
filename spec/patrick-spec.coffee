{exec} = require 'child_process'
fs = require 'fs'
path = require 'path'

_ = require 'underscore'
git = require 'git-utils'
rm = require('rimraf').sync
tmp = require 'tmp'
cp = require('wrench').copyDirSyncRecursive

patrick = require '../lib/patrick'

describe 'patrick', ->
  [snapshotHandler, mirrorHandler, sourceRepo, targetRepo, sourcePath, targetPath] = []

  waitsForCommand = (command, options, callback) ->
    [callback, options] = [options] if _.isFunction(options)

    finished = false
    error = null
    exec command, options, (err, stdout, stderr) ->
      error = err
      console.error 'Command failed', command, arguments if err?
      finished = true

    waitsFor command, ->
      finished

    runs ->
      expect(error).toBeFalsy()
      callback?()

  waitsForSnapshot = (callback) ->
    runs ->
      patrick.snapshot(sourcePath, snapshotHandler)

    waitsFor 'snapshot handler', ->
      snapshotHandler.callCount > 0

    runs ->
      [snapshotError, snapshot] = snapshotHandler.argsForCall[0]
      expect(snapshotError).toBeFalsy()
      expect(snapshot).not.toBeNull()
      patrick.mirror(targetPath, snapshot, mirrorHandler)

    waitsFor 'mirror handler', ->
      mirrorHandler.callCount > 0

    runs ->
      [mirrorError] = mirrorHandler.argsForCall[0]
      expect(mirrorError).toBeNull()
      callback?()

  beforeEach ->
    sourcePath = null
    targetPath = null
    snapshotHandler = jasmine.createSpy('snapshot handler')
    mirrorHandler = jasmine.createSpy('mirror handler')

    tmp.dir (error, tempPath) -> sourcePath = tempPath
    tmp.dir (error, tempPath) -> targetPath = tempPath
    waitsFor 'tmp files', -> sourcePath and targetPath

    runs ->
      cp(path.join(__dirname, 'fixtures', 'ahead.git'), path.join(sourcePath, '.git'))
      sourceRepo = git.open(sourcePath)
      sourceRepo.setConfigValue('remote.origin.url', "file://#{sourcePath}")
      waitsForCommand 'git reset --hard HEAD', {cwd: sourcePath}

  describe 'when the target repository exists', ->
    beforeEach ->
      cp(path.join(__dirname, 'fixtures', 'master.git'), path.join(targetPath, '.git'))
      targetRepo = git.open(targetPath)
      waitsForCommand 'git reset --hard HEAD', {cwd: targetPath}

    describe 'when the source has unpushed changes', ->
      describe 'when the target has no unpushed changes', ->
        it 'applies the unpushed changes to the target repo and updates the target HEAD', ->
          waitsForSnapshot ->
            expect(targetRepo.getHead()).toBe sourceRepo.getHead()
            expect(targetRepo.getReferenceTarget('HEAD')).toBe sourceRepo.getReferenceTarget('HEAD')
            expect(targetRepo.getStatus()).toEqual {}

    describe 'when the source repo has changes in the working directory', ->
      beforeEach ->
        runs ->
          fs.writeFileSync(path.join(sourcePath, 'a.txt'), 'COOL BEANS')
          fs.unlinkSync(path.join(sourcePath, 'b.txt'))
        waitsForSnapshot()

      it "applies the changes to the target repo's working directory", ->
        expect(targetRepo.getHead()).toBe sourceRepo.getHead()
        expect(targetRepo.getReferenceTarget('HEAD')).toBe sourceRepo.getReferenceTarget('HEAD')
        expect(targetRepo.getStatus()).toEqual sourceRepo.getStatus()
        expect(fs.readFileSync(path.join(targetPath, 'a.txt'), 'utf8')).toBe 'COOL BEANS'
        expect(fs.existsSync(path.join(targetPath, 'b.txt'))).toBe false


  describe "when the target repository does not exist", ->
    it "clones the repository to the target path and updates the target HEAD", ->
      waitsForSnapshot ->
        targetRepo = git.open(targetPath)
        expect(targetRepo).toBeTruthy()
        expect(targetRepo.getHead()).toBe sourceRepo.getHead()
        expect(targetRepo.getReferenceTarget('HEAD')).toBe sourceRepo.getReferenceTarget('HEAD')
        expect(targetRepo.getStatus()).toEqual {}

  describe 'when the target has unpushed changes', ->
    beforeEach ->
      cp(path.join(__dirname, 'fixtures', 'ahead.git'), path.join(targetPath, '.git'))
      targetRepo = git.open(targetPath)
      waitsForCommand 'git reset --hard HEAD', {cwd: targetPath}

    it 'creates and checks out a new branch at the source HEAD', ->
      waitsForCommand 'touch new.txt && git add new.txt && git ci -am"new"', {cwd: targetPath}
      waitsForSnapshot ->
        expect(targetRepo.getShortHead()).toBe 'master-1'
        expect(targetRepo.getReferenceTarget('HEAD')).toBe sourceRepo.getReferenceTarget('HEAD')
        expect(targetRepo.getStatus()).toEqual {}
