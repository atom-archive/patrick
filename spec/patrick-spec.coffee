child_process = require 'child_process'
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

  waitsForCommand = (command, options) ->
    finished = false
    error = null
    child_process.exec command, options, (err, stdout, stderr) ->
      error = err
      console.error 'Command failed', command, arguments if err?
      finished = true

    waitsFor command, ->
      finished

    runs ->
      expect(error).toBeFalsy()

  waitsForSnapshot = (mirrorOptions={})->
    runs ->
      patrick.snapshot(sourcePath, snapshotHandler)

    waitsFor 'snapshot handler', ->
      snapshotHandler.callCount > 0

    runs ->
      [snapshotError, snapshot] = snapshotHandler.argsForCall[0]
      expect(snapshotError).toBeFalsy()
      expect(snapshot).not.toBeNull()
      patrick.mirror(targetPath, snapshot, mirrorOptions, mirrorHandler)

    waitsFor 'mirror handler', ->
      mirrorHandler.callCount > 0

    runs ->
      [mirrorError] = mirrorHandler.argsForCall[0]
      expect(mirrorError).toBeFalsy()

  waitsForSourceRepo = (name) ->
    runs ->
      cp(path.join(__dirname, 'fixtures', name), path.join(sourcePath, '.git'))
      sourceRepo = git.open(sourcePath)
      sourceRepo.setConfigValue('remote.origin.url', "file://#{sourcePath}")
      waitsForCommand 'git reset --hard HEAD', {cwd: sourcePath}

  waitsForTargetRepo = (name) ->
    runs ->
      cp(path.join(__dirname, 'fixtures', name), path.join(targetPath, '.git'))
      targetRepo = git.open(targetPath)
      targetRepo.setConfigValue('remote.origin.url', "file://#{sourcePath}")
      waitsForCommand 'git reset --hard HEAD', {cwd: targetPath}

  beforeEach ->
    sourcePath = null
    targetPath = null
    snapshotHandler = jasmine.createSpy('snapshot handler')
    mirrorHandler = jasmine.createSpy('mirror handler')

    tmp.dir (error, tempPath) -> sourcePath = tempPath
    tmp.dir (error, tempPath) -> targetPath = tempPath
    waitsFor 'tmp files', -> sourcePath and targetPath

    waitsForSourceRepo 'ahead.git'

  describe 'when the source has unpushed changes', ->
    describe 'when the target has no unpushed changes', ->
      it 'applies the unpushed changes to the target repo and updates the target HEAD', ->
        waitsForTargetRepo 'master.git'
        waitsForSnapshot()

        runs ->
          expect(targetRepo.getHead()).toBe sourceRepo.getHead()
          expect(targetRepo.getReferenceTarget('HEAD')).toBe sourceRepo.getReferenceTarget('HEAD')
          expect(targetRepo.getStatus()).toEqual {}

  describe 'when the source repo has changes in the working directory', ->
    it "applies the changes to the target repo's working directory", ->
      waitsForTargetRepo 'master.git'

      runs ->
        fs.writeFileSync(path.join(sourcePath, 'a.txt'), 'COOL BEANS')
        fs.writeFileSync(path.join(sourcePath, 'a1.txt'), 'NEW BEANS')
        fs.unlinkSync(path.join(sourcePath, 'b.txt'))

      waitsForSnapshot()

      runs ->
        expect(targetRepo.getHead()).toBe sourceRepo.getHead()
        expect(targetRepo.getReferenceTarget('HEAD')).toBe sourceRepo.getReferenceTarget('HEAD')
        expect(targetRepo.getStatus()).toEqual sourceRepo.getStatus()
        expect(fs.readFileSync(path.join(targetPath, 'a.txt'), 'utf8')).toBe 'COOL BEANS'
        expect(fs.existsSync(path.join(targetPath, 'b.txt'))).toBe false
        expect(fs.readFileSync(path.join(targetPath, 'a1.txt'), 'utf8')).toBe 'NEW BEANS'

  describe "when the target repository does not exist", ->
    it "clones the repository to the target path and updates the target HEAD", ->
      waitsForSnapshot()

      runs ->
        targetRepo = git.open(targetPath)
        expect(targetRepo).toBeTruthy()
        expect(targetRepo.getHead()).toBe sourceRepo.getHead()
        expect(targetRepo.getReferenceTarget('HEAD')).toBe sourceRepo.getReferenceTarget('HEAD')
        expect(targetRepo.getStatus()).toEqual {}

  describe 'when the target has unpushed changes', ->
    it 'creates and checks out a new branch at the source HEAD', ->
      fs.writeFileSync(path.join(targetPath, 'new.txt'), '')

      waitsForTargetRepo 'ahead.git'

      runs ->
        waitsForCommand 'git add new.txt && git commit -am"new"', {cwd: targetPath}

      waitsForSnapshot()

      runs ->
        expect(targetRepo.getShortHead()).toBe 'master-1'
        expect(targetRepo.getReferenceTarget('HEAD')).toBe sourceRepo.getReferenceTarget('HEAD')
        expect(targetRepo.getStatus()).toEqual {}

  describe 'when the target has working directory changes', ->
    describe 'when the changes are the same as in the source working directory', ->
      it 'mirrors the snapshot successfully', ->
        waitsForTargetRepo 'ahead.git'

        runs ->
          fs.writeFileSync(path.join(sourcePath, 'a.txt'), 'COOL BEANS')
          fs.writeFileSync(path.join(sourcePath, 'a1.txt'), 'NEW BEANS')
          fs.writeFileSync(path.join(sourcePath, 'a2.txt'), 'NEWER BEANS')
          fs.unlinkSync(path.join(sourcePath, 'b.txt'))
          fs.writeFileSync(path.join(targetPath , 'a.txt'), 'COOL BEANS')
          fs.writeFileSync(path.join(targetPath, 'a1.txt'), 'NEW BEANS')
          fs.unlinkSync(path.join(targetPath, 'b.txt'))

        waitsForSnapshot()

        runs ->
          expect(fs.readFileSync(path.join(targetPath, 'a.txt'), 'utf8')).toBe 'COOL BEANS'
          expect(fs.readFileSync(path.join(targetPath, 'a1.txt'), 'utf8')).toBe 'NEW BEANS'
          expect(fs.readFileSync(path.join(targetPath, 'a2.txt'), 'utf8')).toBe 'NEWER BEANS'
          expect(fs.existsSync(path.join(targetPath, 'b.txt'))).toBe false

    describe 'when the changes differ from the source repository', ->
      it 'fails to mirror the snapshot', ->
        fs.writeFileSync(path.join(targetPath, 'dirty.txt'), '')

        waitsForTargetRepo 'ahead.git'

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
          expect(mirrorError).toBeTruthy()

  describe 'when the source and target have the same HEAD', ->
    it 'does not change the target HEAD', ->
      waitsForTargetRepo 'ahead.git'
      waitsForSnapshot()
      runs ->
        expect(targetRepo.getHead()).toBe sourceRepo.getHead()
        expect(targetRepo.getReferenceTarget('HEAD')).toBe sourceRepo.getReferenceTarget('HEAD')
        expect(targetRepo.getStatus()).toEqual {}

  describe 'when the source branch does not exist in the target repository', ->
    it 'creates and checks out a new branch at the source HEAD', ->
      waitsForTargetRepo 'master.git'
      waitsForCommand 'git checkout -b blaster', {cwd: sourcePath}
      waitsForSnapshot()
      runs ->
        expect(targetRepo.getHead()).toBe sourceRepo.getHead()
        expect(targetRepo.getReferenceTarget('HEAD')).toBe sourceRepo.getReferenceTarget('HEAD')
        expect(targetRepo.getStatus()).toEqual {}

  describe 'when the target location and the source use the same ssh URL', ->
    it 'mirrors the snapshot', ->
      waitsForTargetRepo 'master.git'
      execSpy = null

      runs ->
        sourceRepo.setConfigValue('remote.origin.url', 'git@github.com:/another/repo')
        targetRepo.setConfigValue('remote.origin.url', 'git@github.com:/another/repo')
        patrick.snapshot(sourcePath, snapshotHandler)

      waitsFor 'snapshot handler', ->
        snapshotHandler.callCount > 0

      runs ->
        [snapshotError, snapshot] = snapshotHandler.argsForCall[0]
        expect(snapshotError).toBeFalsy()
        expect(snapshot).not.toBeNull()
        execSpy = spyOn(child_process, 'exec')
        patrick.mirror(targetPath, snapshot, mirrorHandler)

      waitsFor 'mirror handler', ->
        execSpy.callCount > 0 or mirrorHandler.callCount > 0

      runs ->
        expect(execSpy.callCount).toBeGreaterThan 0

        [command] = execSpy.argsForCall[0] if execSpy.argsForCall[0]
        expect(command).toBe 'git fetch git@github.com:/another/repo'

  describe 'when the target location has a different URL than the source', ->
    it 'fails to mirror the snapshot', ->
      waitsForTargetRepo 'master.git'

      runs ->
        targetRepo.setConfigValue('remote.origin.url', 'http://github.com/another/repo')
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
        expect(mirrorError).toBeTruthy()

  describe 'when a progress callback is given', ->
    it 'calls back for each operation with a description, command, and total operation count', ->
      progressCallback = jasmine.createSpy('progress callback')

      waitsForTargetRepo 'master.git'
      waitsForSnapshot({progressCallback})

      runs ->
        expect(progressCallback.callCount).toBe 2
        expect(progressCallback.argsForCall[0][0]).toBeTruthy()
        expect(progressCallback.argsForCall[0][1]).toBeTruthy()
        expect(progressCallback.argsForCall[0][2]).toBe 2
        expect(progressCallback.argsForCall[1][0]).toBeTruthy()
        expect(progressCallback.argsForCall[1][1]).toBeTruthy()
        expect(progressCallback.argsForCall[1][2]).toBe 2
