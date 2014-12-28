# mologie:computation-observer
# Copyright 2014 Oliver Kuckertz <oliver.kuckertz@mologie.de>
# See COPYING for license information.

if Meteor.isClient
	
	#
	# Unit tests
	#
	
	makeCo = -> new ComputationObserver
		computation: []
		valueField: "v"
		events: []
	
	# Test start
	Tinytest.add "ComputationObserver.start", (test) ->
		co = makeCo()
		co._provider = -> []
		co.start()
		co.stop()
		co._provider = -> undefined
		test.throws -> co.start()
		co.stop()
		co._provider = []
		co.start()
		co.stop()
		co._provider = undefined
		test.throws -> co.start()
		co.stop()
	
	# Test getting object value
	Tinytest.add "ComputationObserver._objectValue", (test) ->
		co = makeCo()
		test.equal co._objectValue({v: "a"}), "a"
		test.throws -> co._objectValue({v: []})
		test.throws -> co._objectValue({q: "a"})
	
	# Test basic logic of diffing algorithm
	Tinytest.add "ComputationObserver._diffKeys", (test) ->
		co = makeCo()
		test.equal co._diffKeys([{v: '1'}, {v: '2'}, {v: '3'}], [{v: '1'}, {v: '2'}]),
			{added: [], changed: ['1', '2'], removed: ['3']}
		test.equal co._diffKeys([{v: '1'}, {v: '2'}, {v: '3'}], [{v: '1'}, {v: '4'}]),
			{added: ['4'], changed: ['1'], removed: ['2', '3']}
		test.equal co._diffKeys([{v: '1'}, {v: '2'}, {v: '3'}], [{v: '4'}, {v: '1'}]),
			{added: ['4'], changed: ['1'], removed: ['2', '3']}
	
	# Test correct formatting of output
	Tinytest.add "ComputationObserver._diffSnapshots", (test) ->
		co = makeCo()
		a = [{v: '1'}, {v: '2'}, {v: '3'}]
		b = [{v: '1'}, {v: '2'}, {v: '4'}]
		e = {
			added: [{v: '4'}]
			changed: [{current: {v: '1'}, prev: {v: '1'}}, {current: {v: '2'}, prev: {v: '2'}}]
			removed: [{v: '3'}]
		}
		test.equal co._diffSnapshots(a, b), e
	
	# Test forwarding of changeset
	Tinytest.add "ComputationObserver._applyChangeSet", (test) ->
		co = makeCo()
		expected =
			added: [{v: '4'}]
			changed: [{current: {v: '1'}, prev: {v: '1'}}, {current: {v: '2'}, prev: {v: '2'}}]
			removed: [{v: '3'}]
		batchBeginCalled = false
		batchEndCalled = false
		co._events =
			batchBegin: ->
				test.isFalse batchBeginCalled
				batchBeginCalled = true
			batchEnd: ->
				test.isFalse batchEndCalled
				batchEndCalled = true
			added: (doc) ->
				test.isTrue batchBeginCalled
				test.isFalse batchEndCalled
				e = expected.added.shift()
				test.equal e, doc
			changed: (doc, prevDoc) ->
				test.isTrue batchBeginCalled
				test.isFalse batchEndCalled
				e = expected.changed.shift()
				test.equal e.current, doc
				test.equal e.prev, prevDoc
			removed: (doc) ->
				test.isTrue batchBeginCalled
				test.isFalse batchEndCalled
				e = expected.removed.shift()
				test.equal e, doc
		a = [{v: '1'}, {v: '2'}, {v: '3'}]
		b = [{v: '1'}, {v: '2'}, {v: '4'}]
		changeset = co._diffSnapshots a, b
		co._applyChangeSet changeset
		test.isTrue batchBeginCalled
		test.isTrue batchEndCalled
		test.length expected.added, 0
		test.length expected.changed, 0
		test.length expected.removed, 0
	
	#
	# Integration tests
	#
	
	class EventLogger
		constructor: (@test) ->
			@reset()
		expectAdded: (doc) -> @expected.push {added: doc}
		expectChanged: (doc, prevDoc) -> @expected.push {changed: doc, prev: prevDoc}
		expectRemoved: (doc) -> @expected.push {removed: doc}
		assert: ->
			Tracker.flush()
			@test.equal @log, @expected
			@reset()	
		reset: ->
			@log = []
			@expected = []
		eventMap: ->
			added: (doc) => @log.push {added: doc}
			changed: (doc, prevDoc) => @log.push {changed: doc, prev: prevDoc}
			removed: (doc) => @log.push {removed: doc}
	
	# Reactive function using a ReactiveVar
	Tinytest.add "ComputationObserver with reactive data source", (test) ->
		rv = new ReactiveVar [{v: 'first'}]
		lg = new EventLogger test
		co = new ComputationObserver
			computation: -> rv.get()
			valueField: "v"
			events: lg.eventMap()
		co.start()
		
		lg.expectAdded {v: 'first'}
		lg.assert()
		
		rv.set [{v: 'a'}, {v: 'b'}]
		lg.expectAdded {v: 'a'}
		lg.expectAdded {v: 'b'}
		lg.expectRemoved {v: 'first'}
		lg.assert()
		
		rv.set [{v: 'a'}]
		lg.expectChanged {v: 'a'}, {v: 'a'}
		lg.expectRemoved {v: 'b'}
		lg.assert()
	
	# Non-reactive function returning a changing Mongo.Cursor
	Tinytest.add "ComputationObserver with non-reactive Mongo.Cursor", (test) ->
		mc = new Mongo.Collection null
		firstId = mc.insert {x: 'first'}
		secondId = mc.insert {x: 'second'}
		
		lg = new EventLogger test
		co = new ComputationObserver
			computation: -> mc.find()
			valueField: "_id"
			events: lg.eventMap()
		co.start()
		
		lg.expectAdded {x: 'first', _id: firstId}
		lg.expectAdded {x: 'second', _id: secondId}
		lg.assert()
		
		thirdId = mc.insert {x: 'third'}
		lg.expectAdded {x: 'third', _id: thirdId}
		lg.assert()
		
		mc.update firstId, {x: 'first updated'}
		mc.remove secondId
		lg.expectChanged {x: 'first updated', _id: firstId}, {x: 'first', _id: firstId}
		lg.expectRemoved {x: 'second', _id: secondId}
		lg.assert()

	# Reactive function returning a static Mongo.Cursor
	Tinytest.add "ComputationObserver with reactive Mongo.Cursor", (test) ->
		mc1 = new Mongo.Collection null
		id1 = mc1.insert {name: 'a'}
		id2 = mc1.insert {name: 'b'}
		
		mc2 = new Mongo.Collection null
		id3 = mc2.insert {name: 'b'}
		id4 = mc2.insert {name: 'c'}
		
		rv = new ReactiveVar false
		lg = new EventLogger test
		co = new ComputationObserver
			computation: ->
				if rv.get() then mc2.find() else mc1.find()
			valueField: "name"
			events: lg.eventMap()
		co._debug = true
		co.start()
		
		lg.expectAdded {name: 'a', _id: id1}
		lg.expectAdded {name: 'b', _id: id2}
		lg.assert()
		
		rv.set true
		Tracker.flush()
		
		lg.expectAdded {name: 'c', _id: id4}
		lg.expectChanged {name: 'b', _id: id3}, {name: 'b', _id: id2}
		lg.expectRemoved {name: 'a', _id: id1}
		lg.assert()

	# Reactive function triggering array to cursor migration
	Tinytest.add "ComputationObserver array to cursor migration", (test) ->
		mc = new Mongo.Collection null
		id1 = mc.insert {name: 'a'}
		id2 = mc.insert {name: 'b'}
		
		ar = [
			{name: 'b'}
			{name: 'c'}
		]
		
		rv = new ReactiveVar false
		lg = new EventLogger test
		co = new ComputationObserver
			computation: ->
				if rv.get() then ar else mc.find()
			valueField: "name"
			events: lg.eventMap()
		co._debug = true
		co.start()
		
		lg.expectAdded {name: 'a', _id: id1}
		lg.expectAdded {name: 'b', _id: id2}
		lg.assert()
		
		rv.set true
		Tracker.flush()
		
		lg.expectAdded {name: 'c'}
		lg.expectChanged {name: 'b'}, {name: 'b', _id: id2}
		lg.expectRemoved {name: 'a', _id: id1}
		lg.assert()
	
	# Reactive function triggering cursor to array migration
	Tinytest.add "ComputationObserver cursor to array migration", (test) ->
		ar = [
			{name: 'a'}
			{name: 'b'}
		]
		
		mc = new Mongo.Collection null
		id1 = mc.insert {name: 'b'}
		id2 = mc.insert {name: 'c'}
		
		rv = new ReactiveVar false
		lg = new EventLogger test
		co = new ComputationObserver
			computation: ->
				if rv.get() then mc.find() else ar
			valueField: "name"
			events: lg.eventMap()
		co._debug = true
		co.start()
		
		lg.expectAdded {name: 'a'}
		lg.expectAdded {name: 'b'}
		lg.assert()
		
		rv.set true
		Tracker.flush()
		
		lg.expectAdded {name: 'c', _id: id2}
		lg.expectChanged {name: 'b', _id: id1}, {name: 'b'}
		lg.expectRemoved {name: 'a'}
		lg.assert()
	
	# Test start/stop/start
	Tinytest.add "ComputationObserver start/stop/start", (test) ->
		rv = new ReactiveVar [{v: 'first'}]
		lg = new EventLogger test
		co = new ComputationObserver
			computation: -> rv.get()
			valueField: "v"
			events: lg.eventMap()
		co.start()
		
		lg.expectAdded {v: 'first'}
		lg.assert()
		
		co.stop()
		
		rv.set [{v: 'a'}, {v: 'b'}]
		Tracker.flush()
		
		rv.set [{v: 'a'}]
		Tracker.flush()
		
		co.start()
		
		lg.expectAdded {v: 'a'}
		lg.expectRemoved {v: 'first'}
		lg.assert()

	# Test start/reset/start
	Tinytest.add "ComputationObserver start/reset/start", (test) ->
		lg = new EventLogger test
		co = new ComputationObserver
			computation: -> [{v: 'first'}, {v: 'second'}]
			valueField: "v"
			events: lg.eventMap()
		co.start()
		
		lg.expectAdded {v: 'first'}
		lg.expectAdded {v: 'second'}
		lg.assert()
		
		co.reset()
		co.start()
		
		lg.expectAdded {v: 'first'}
		lg.expectAdded {v: 'second'}
		lg.assert()
