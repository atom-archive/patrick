tmp = require 'tmp'
syncopy = require '../lib/syncopy'

describe 'syncopy', ->
  [sourcePath, targetPath] = []

  beforeEach ->
    tmp.dir (error, tempPath) -> sourcePath = tempPath
    tmp.dir (error, tempPath) -> targetPath = tempPath
    waitsFor -> sourcePath and targetPath

  describe 'when the target repository exists', ->
    describe 'when the source has unpushed changes', ->
      describe 'when the target has no unpushed changes', ->
        it 'applies the unpushed changes to the target repository and updates the target HEAD', ->
          generateHandler = jasmine.createSpy('generate handler')
          restoreHandler = jasmine.createSpy('restore handler')
          syncopy.generate(sourcePath, generateHandler)

          waitsFor -> generateHandler.callCount is 1

          runs ->
            expect(generateHandler.argsForCall[0][0]).toBeNull()
            snapshot = generateHandler.argsForCall[0][1]
            expect(snapshot).not.toBeNull()

            syncopy.restore(targetPath, snapshot, restoreHandler)

          waitsFor -> restoreHandler.callCount is 1

          runs ->
            expect(restoreHandler.argsForCall[0][0]).toBeNull()
