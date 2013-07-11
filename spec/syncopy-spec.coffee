{exec} = require 'child_process'
path = require 'path'
tmp = require 'tmp'
cp = require('wrench').copyDirSyncRecursive
git = require 'git-utils'

syncopy = require '../lib/syncopy'

describe 'syncopy', ->
  [sourceRepo, targetRepo, sourcePath, targetPath] = []

  beforeEach ->
    tmp.dir (error, tempPath) -> sourcePath = tempPath
    tmp.dir (error, tempPath) -> targetPath = tempPath
    waitsFor 'tmp files', -> sourcePath and targetPath

    runs ->
      cp(path.join(__dirname, 'fixtures', 'ahead.git'), path.join(sourcePath, '.git'))
      sourceRepo = git.open(sourcePath)

  describe 'when the target repository exists', ->
    beforeEach ->
      cp(path.join(__dirname, 'fixtures', 'ahead.git'), path.join(targetPath, '.git'))
      targetRepo = git.open(targetPath)

    describe 'when the source has unpushed changes', ->
      describe 'when the target has no unpushed changes', ->
        beforeEach ->
          finished = false
          exec 'git reset --hard origin/master', {cwd: targetPath}, (error) ->
            expect(error).toBeFalsy()
            finished = true

          waitsFor 'git reset', ->
            finished

        it 'applies the unpushed changes to the target repository and updates the target HEAD', ->
          snapshotHandler = jasmine.createSpy('snapshot handler')
          mirrorHandler = jasmine.createSpy('mirror handler')
          syncopy.snapshot(sourcePath, snapshotHandler)

          waitsFor 'snapshot handler', ->
            snapshotHandler.callCount > 0

          runs ->
            [snapshotError, snapshot] = snapshotHandler.argsForCall[0]
            expect(snapshotError).toBeNull()
            expect(snapshot).not.toBeNull()

            syncopy.mirror(targetPath, snapshot, mirrorHandler)

          waitsFor 'mirror handler', ->
            mirrorHandler.callCount > 0

          runs ->
            [mirrorError] = mirrorHandler.argsForCall[0]
            expect(mirrorError).toBeNull()
