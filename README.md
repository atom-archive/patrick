# syncopy

Synchronize a Git repository from one place to another.

## Usage

```coffeescript
syncopy = require 'syncopy'
```

### Generate a snapshot

```coffeescript
syncopy.snapshot '/repos/here', (error, snapshot) ->
  if error?
    console.error('snapshot failed', error)
  else
    console.log('snapshot succeeded')
```

### Mirror a snapshot

```coffeescript
syncopy.mirror snapshot, '/repos/there', (error) ->
  if error?
    console.error('mirror failed', error)
  else
    console.log('mirror succeeded')
```
