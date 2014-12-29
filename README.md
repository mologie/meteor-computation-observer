computation-observer
====================

This package provides the class `ComputationObserver`, which accepts a reactive
function and returns a stream of incremental changes, just like LiveQuery. Its
only limitation is that all documents must have a unique and static identifying
property. Should the given function return a Mongo.Cursor, `ComputationObserver`
will automatically use the cursor's `observe` function.

Because this package depends on Meteor's Tracker, `ComputationObserver` is
available exclusively on the client.

Example
-------

A common usage scenario for this packge is enabling `observe`-like behavior
for client-side reactive queries as illustrated in the following example.

```js
getAnimals = ->
	filter = Session.get "shelter.filterBySpecies"
	if filter
		Animals.find {species: {$in: filter}}
	else
		Animals.find {}

Template.shelter.rendered = ->
  list = new AnimalListController @('.animal-list')
  @adorableObserver = new ComputationObserver
  	computation: getAnimals
  	valueField: "_id"
  	events:
      added: (animal) -> list.add(animal)
      changed: (animal, before) -> list.update(animal)
      removed: (animal) -> list.remove(animal)
  @adorableObserver.start()

Template.shelter.destroyed = ->
  @adorableObserver.stop()
```

Usage
-----

<table width="100%">
	<tr>
		<th valign="top" colspan="4" align="left"><a href="#general" name="general">Options</a></th>
	</tr>
	<tr>
		<th valign="top" width="120px" align="left">Option</th>
		<th valign="top" align="left">Description</th>
		<th valign="top" width="60px" align="left">Type</th>
	</tr>
	<tr>
		<td valign="top"><code>computation</code></td>
		<td valign="top">A function returning either an array of objects, or a <code>Mongo.Cursor</code>. The function is re-evaluated automatically using <code>Tracker</code> when its reactive data sources change.</td>
		<td valign="top"><code>function|array</code></td>
	</tr>
	<tr>
		<td valign="top"><code>valueField</code></td>
		<td valign="top">The name of a property which is present, static and unique for all documents returned by the computation.</td>
		<td valign="top"><code>string</code></td>
	</tr>
	<tr>
		<td valign="top"><code>events</code></td>
		<td valign="top">The event map, which receives a stream of incremental updates.</td>
		<td valign="top"><code>event map</code></td>
	</tr>
	<tr>
		<th valign="top" colspan="4" align="left"><a href="#general" name="general">Event map</a></th>
	</tr>
	<tr>
		<th valign="top" width="120px" align="left">Event</th>
		<th valign="top" align="left">Description</th>
		<th valign="top" width="60px" align="left">Return value</th>
	</tr>
	<tr>
		<td valign="top"><code>added(doc)</code></td>
		<td valign="top">Called when a new document was returned by the computation. Also called from within `start` once for each document already present in the computation's results.</td>
		<td valign="top"><code>none</code></td>
	</tr>
	<tr>
		<td valign="top"><code>changed(doc, prevDoc)</code></td>
		<td valign="top"><i>Does not mean that the document actually changed.</i> One cannot reliably compare objects in JavaScript. You are likely to receive one change event for each object that is still present in the computation's results each time the computation is re-evaluated.</td>
		<td valign="top"><code>none</code></td>
	</tr>
	<tr>
		<td valign="top"><code>removed(doc)</code></td>
		<td valign="top">Called when a new document disappeared from the results of the computation.</td>
		<td valign="top"><code>none</code></td>
	</tr>
	<tr>
		<th valign="top" colspan="4" align="left"><a href="#general" name="general">Functions</a></th>
	</tr>
	<tr>
		<th valign="top" width="120px" align="left">Function</th>
		<th valign="top" align="left">Description</th>
		<th valign="top" width="60px" align="left">Return value</th>
	</tr>
	<tr>
		<td valign="top"><code>start()</code></td>
		<td valign="top">Begin sending incremental update events. Calling <code>start</code> multiple times has no effect.</td>
		<td valign="top"><code>none</code></td>
	</tr>
		<td valign="top"><code>stop()</code></td>
		<td valign="top">End sending incremental updates. The <code>start</code> function can be called at any time after calling this function.</td>
		<td valign="top"><code>none</code></td>
	</tr>
	<tr>
		<td valign="top"><code>reset()</code></td>
		<td valign="top">Stop and discard the current state. Calling <code>start</code> after calling <code>reset</code> therefore only results in an inital set of <i>added</i> events being sent.</td>
		<td valign="top"><code>none</code></td>
	</tr>
	<tr>
		<td valign="top"><code>getSnapshot()</code></td>
		<td valign="top">Get a full snapshot of all documents that have previously been sent incrementally. Does <i>not</i> register a dependency on the data source.</td>
		<td valign="top"><code>[Object]</code></td>
	</tr>
</table>

Caveats
-------

* `ComputationObserver` uses Tracker's `autorun` and starts live queries. You
  must call its `stop` function when discarding it, or these queries will
  run forever. Beware of the Tracker - you might be running in a reactive
  computation yourself.
* You can pass an array through the `computation` setting, but this does not get
  you any reactive behavior. This turned out to be a common typo when using
  CoffeeScript.
* When the value field is missing from any document returned by its function,
  `ComputationObserver` will throw an exception.

License
-------

This project is licensed under the MIT license.
