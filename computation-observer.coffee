# mologie:computation-observer
# Copyright 2014 Oliver Kuckertz <oliver.kuckertz@mologie.de>
# See COPYING for license information.

# The ComputationObserver class provides an API very similar to that of
# Mongo.Cursor for all reactive computations. The only limitation is that all
# result sets must share a unique identifying property (like _id in Mongo).

# TODO Keep track of the cursor's output. When replacing the cursor, do a full diff.
# TODO Allow for changing between arrays and cursors

makeObject = (id, fields) ->
	object = _.clone fields
	object._id = id
	object

class ComputationObserver
	constructor: (options) ->
		@_computation = options.computation
		@_valueField = options.valueField
		@_events = options.events
	
	start: ->
		if typeof @_computation is "function"
			# Reactive data source
			@_computation = Tracker.autorun => @_takeSnapshot()
		else if _.isArray @_computation
			# Static data source
			@_snapshot = @_computation
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
		@_snapshot = @_computation()
		
		if @_snapshot instanceof Mongo.Cursor
			# Begin receiving stream of results using live query interface
			@_ensureResultTypeUnchanged "cursor"
			@_liveQuery.stop() if @_liveQuery?
			@_liveQuery = @_observeChangesInQuery @_snapshot
		else if _.isArray @_snapshot
			# Diff current snapshot against previous snapshot, if any
			@_ensureResultTypeUnchanged "array"
			if @_previousSnapshot
				@_diffSnapshots @_previousSnapshot, @_snapshot
			else
				@_addAll @_snapshot
		else
			throw new Error "computation function must return an array or a Mongo.Cursor instance"
	
	_ensureResultTypeUnchanged: (type) ->
		# Sorry about this. :/ Changing result types are is supported because
		# this class does not keep track of what is actually being returned by
		# Mongo.Cursor's observe function. Maybe another time.
		if @_resultType?
			if type is not @_resultType
				throw new Error "computation must not change result type"
		else
			@_resultType = type
	
	_addAll: (collection) ->
		@_events.batchBegin() if @_events.batchBegin?
		if not @_events.added?
			return
		for doc in collection
			@_events.added doc
		@_events.batchEnd() if @_events.batchEnd?
	
	_observeChangesInQuery: (cursor) ->
		watchers = {}
		if @_events.added? then watchers.added = (doc) => @_events.added doc
		if @_events.changed? then watchers.changed = (newDoc, oldDoc) => @_events.changed newDoc, oldDoc
		if @_events.removed? then watchers.removed = (oldDoc) => @_events.removed oldDoc
		cursor.observe watchers
	
	_objectValue: (object) ->
		object[@_valueField] ? ""
	
	_diffSnapshots: (previousSnapshot, currentSnapshot) ->
		# Extract keys
		previousKeys = _.pluck previousSnapshot, @_valueField
		currentKeys = _.pluck currentSnapshot, @_valueField
		
		# Map objects to keys
		previous = []
		current = []
		for object in previousSnapshot
			previous[@_objectValue object] = object
		for object in currentSnapshot
			current[@_objectValue object] = object
		
		# Begin batch update
		@_events.batchBegin() if @_events.batchBegin?
		
		# Find added documents
		if @_events.added?
			addedKeys = _.difference currentKeys, previousKeys
			for value in addedKeys
				@_events.added current[value]
		
		# Find changed documents
		if @_events.changed?
			changedKeys = _.intersection previousSnapshot, currentSnapshot
			for value in changedKeys
				@_events.changed current[value], previous[value]
		
		# Find removed documents
		if @_events.removed?
			removedKeys = _.difference previousKeys, currentKeys
			for value in removedKeys
				@_events.removed previous[value]
		
		# End batch update
		@_events.batchEnd() if @_events.batchEnd?


@ComputationObserver = ComputationObserver
