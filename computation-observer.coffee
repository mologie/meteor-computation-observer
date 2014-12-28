# mologie:computation-observer
# Copyright 2014 Oliver Kuckertz <oliver.kuckertz@mologie.de>
# See COPYING for license information.

# The ComputationObserver class provides an API very similar to that of
# Mongo.Cursor for all reactive computations. The only limitation is that all
# result sets must share a unique identifying property (like _id in Mongo).

class ComputationObserver
	constructor: (options) ->
		@_provider = options.computation
		@_valueField = options.valueField
		@_events = options.events
	
	start: ->
		if typeof @_provider is "function"
			# Reactive data source
			@_computation = Tracker.autorun => @_takeSnapshot()
		else if _.isArray @_provider
			# Static data source
			@_snapshot = @_provider
			@_addAll @_snapshot
		else
			throw new Error "computation must be either an array or a function returning an array"
	
	stop: ->
		if @_computation?
			@_computation.stop()
			delete @_computation
		if @_liveQuery?
			@_liveQuery.stop()
			delete @_liveQuery
		delete @_previousSnapshot
		delete @_snapshot
	
	getSnapshot: ->
		if @_snapshot instanceof Mongo.Cursor
			Tracker.nonreactive => @_snapshot.fetch()
		else
			@_snapshot
	
	_takeSnapshot: ->
		@_previousSnapshot = @_snapshot
		@_snapshot = @_provider()
		if @_snapshot instanceof Mongo.Cursor
			@_processCursor()
		else if _.isArray @_snapshot
			@_processSnapshot()
		else
			throw new Error "computation function must return an array or a Mongo.Cursor instance"
	
	_processCursor: ->
		cursor = @_snapshot
		if @_liveQuery
			# Migrate cursor to cursor
			@_liveQuery.stop()
			delete @_liveQuery
			prevCursor = @_previousSnapshot
			@_migrateCursorToCursor prevCursor, cursor
		else if @_previousSnapshot
			# Migrate snapshot to cursor
			@_migrateArrayToCursor @_previousSnapshot, cursor
		else
			# Trivial case
			@_observeCursor cursor
	
	_processSnapshot: ->
		if @_liveQuery
			# Migrate cursor to snapshot
			@_liveQuery.stop()
			delete @_liveQuery
			prevCursor = @_previousSnapshot
			@_migrateCursorToArray prevCursor, @_snapshot
		else if @_previousSnapshot
			# Migrate snapshot to snapshot
			@_migrateArrayToArray @_previousSnapshot, @_snapshot
		else
			# Trivial case
			@_addAll @_snapshot
	
	_migrateCursorToCursor: (prevCursor, newCursor) ->
		# Get full snapshot of the old data
		prevData = Tracker.nonreactive -> prevCursor.fetch()
		prevKeys = _.pluck prevData, @_valueField
		
		# Continue like snapshot to cursor
		@_migrateArrayToCursor prevData, newCursor
	
	_migrateCursorToArray: (prevCursor, newSnapshot) ->
		# Get full snapshot of the old data
		prevData = Tracker.nonreactive -> prevCursor.fetch()
		prevKeys = _.pluck prevData, @_valueField
		
		# Continue like snapshot to snapshot
		@_migrateArrayToArray prevData, newSnapshot
	
	_migrateArrayToCursor: (prevSnapshot, newCursor) ->
		# Live queries do not provide an option for replacing the event object.
		# Since we cannot cancel the live query without receiving another full
		# set of data, we instead use an event map and forwarder functions for
		# redirecting incremental updates.
		initialSnapshot = []
		eventsMap =
			added: (doc) -> initialSnapshot.push(doc)
		
		# Get initial data set from new cursor
		@_liveQuery = newCursor.observe
			added: (doc) -> eventsMap.added doc if eventsMap.added?
			changed: (newDoc, prevDoc) -> eventsMap.changed newDoc, prevDoc if eventsMap.changed?
			removed: (prevDoc) -> eventsMap.removed prevDoc if eventsMap.removed?
		
		# Continue like array to array
		@_migrateArrayToArray prevSnapshot, initialSnapshot
		
		# Redirect events to @_events
		delete eventsMap.added
		_.extend eventsMap, @_events
	
	_migrateArrayToArray: (prevSnapshot, newSnapshot) ->
		# Generate and apply changeset
		changeset = @_diffSnapshots prevSnapshot, newSnapshot
		@_applyChangeSet changeset
	
	_observeCursor: (cursor) ->
		# Initial setup: Start a live query
		observers = {}
		observers.added = @_events.added if @_events.added?
		observers.changed = @_events.changed if @_events.changed?
		observers.removed = @_events.removed if @_events.removed?
		@_events.batchBegin() if @_events.batchBegin?
		@_liveQuery = cursor.observe observers
		@_events.batchEnd() if @_events.batchEnd?
	
	_addAll: (collection) ->
		# Initial setup: Notify delegate about all documents in data set
		@_events.batchBegin() if @_events.batchBegin?
		if not @_events.added?
			return
		for doc in collection
			@_events.added doc
		@_events.batchEnd() if @_events.batchEnd?
	
	_objectValue: (object) ->
		if not object[@_valueField]?
			throw new Error "computation returned object without identifying property '#{@_valueField}'"
		value = object[@_valueField]
		if typeof value isnt "string"
			throw new Error "computation returned object whose identifying property is not a string"
		value
	
	_diffKeys: (previousSnapshot, currentSnapshot) ->
		# Extract keys
		previousKeys = _.pluck previousSnapshot, @_valueField
		currentKeys = _.pluck currentSnapshot, @_valueField
		
		# Calculate difference
		added: _.difference currentKeys, previousKeys
		changed: _.intersection previousKeys, currentKeys
		removed: _.difference previousKeys, currentKeys
	
	_diffSnapshots: (previousSnapshot, currentSnapshot) ->
		# Calculate difference
		diff = @_diffKeys previousSnapshot, currentSnapshot
		
		# Map objects to keys
		previous = {}
		current = {}
		for object in previousSnapshot
			previous[@_objectValue object] = object
		for object in currentSnapshot
			current[@_objectValue object] = object
		
		# Build object collections
		added: _.map diff.added, (key) ->
			current[key]
		changed: _.map diff.changed, (key) ->
			{current: current[key], prev: previous[key]}
		removed: _.map diff.removed, (key) ->
			previous[key]
	
	_applyChangeSet: (changeset) ->
		# Begin batch update
		@_events.batchBegin() if @_events.batchBegin?
		
		# Send changes
		if @_events.added?
			_.each changeset.added, @_events.added
		if @_events.changed?
			_.each changeset.changed, (x) => @_events.changed x.current, x.prev
		if @_events.removed?
			_.each changeset.removed, @_events.removed
		
		# End batch update
		@_events.batchEnd() if @_events.batchEnd?


@ComputationObserver = ComputationObserver
