{exec} = require 'child_process'
fs = require 'fs'
path = require 'path'

tmp = require 'tmp'
cp = require('wrench').copyDirSyncRecursive
git = require 'git-utils'

patrick = require '../lib/patrick'

describe 'patrick', ->
  [snapshotHandler, mirrorHandler, sourceRepo, targetRepo, sourcePath, targetPath] = []

  waitsForCommand = (command, options) ->
    finished = false
    error = null
    exec command, options, (err) ->
      error = err
      finished = true

    waitsFor command, ->
      finished

    runs ->
      expect(error).toBeFalsy()

  waitsForSnapshot = ->
    runs ->
      patrick.snapshot(sourcePath, snapshotHandler)

    waitsFor 'snapshot handler', ->
      snapshotHandler.callCount > 0

    runs ->
      [snapshotError, snapshot] = snapshotHandler.argsForCall[0]
      expect(snapshotError).toBeNull()
      expect(snapshot).not.toBeNull()
      patrick.mirror(targetPath, snapshot, mirrorHandler)

    waitsFor 'mirror handler', ->
      mirrorHandler.callCount > 0

    runs ->
      [mirrorError] = mirrorHandler.argsForCall[0]
      expect(mirrorError).toBeNull()

  beforeEach ->
    snapshotHandler = jasmine.createSpy('snapshot handler')
    mirrorHandler = jasmine.createSpy('mirror handler')

    tmp.dir (error, tempPath) -> sourcePath = tempPath
    tmp.dir (error, tempPath) -> targetPath = tempPath
    waitsFor 'tmp files', -> sourcePath and targetPath

    runs ->
      cp(path.join(__dirname, 'fixtures', 'ahead.git'), path.join(sourcePath, '.git'))
      sourceRepo = git.open(sourcePath)
      waitsForCommand 'git reset --hard HEAD', {cwd: sourcePath}

  describe 'when the target repository exists', ->
    beforeEach ->
      cp(path.join(__dirname, 'fixtures', 'ahead.git'), path.join(targetPath, '.git'))
      targetRepo = git.open(targetPath)
      waitsForCommand 'git reset --hard HEAD', {cwd: targetPath}

    describe 'when the source has unpushed changes', ->
      describe 'when the target has no unpushed changes', ->
        beforeEach ->
          waitsForCommand 'git reset --hard origin/master', {cwd: targetPath}
          waitsForSnapshot()

        it 'applies the unpushed changes to the target repo and updates the target HEAD', ->
          expect(targetRepo.getHead()).toBe sourceRepo.getHead()
          expect(targetRepo.getReferenceTarget('HEAD')).toBe sourceRepo.getReferenceTarget('HEAD')
          expect(targetRepo.getStatus()).toEqual {}

    describe 'when the source repo has changes in the working directory', ->
      beforeEach ->
        runs ->
          fs.writeFileSync(path.join(sourcePath, 'a.txt'), 'COOL BEANS')

        waitsForSnapshot()

      it "applies the changes to the target repo's working directory", ->
        expect(targetRepo.getHead()).toBe sourceRepo.getHead()
        expect(targetRepo.getReferenceTarget('HEAD')).toBe sourceRepo.getReferenceTarget('HEAD')
        expect(targetRepo.getStatus()).toEqual sourceRepo.getStatus()
