# syncopy

Synchronize a Git repository from one place to another.

## Usage

```coffeescript
syncopy = require 'syncopy'
```

### Generate a snapshot

```coffeescript
snapshot = syncopy.generate('/repos/here')
```

### Apply that snapshot

```coffeescript
syncopy.restore(snapshot, '/repos/there')
```
