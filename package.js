Package.describe({
	name:    'mologie:computation-observer',
	summary: 'LiveQuery for arbitrary reactive computations',
	version: '1.0.0',
	git:     'https://github.com/mologie/meteor-computation-observer'
});

Package.onUse(function(api) {
	api.versionsFrom('1.0');
	api.use(['coffeescript', 'underscore'], 'client');
	api.addFiles('computation-observer.coffee', 'client');
	api.export('ComputationObserver', 'client');
});

Package.onTest(function(api) {
	api.use(['mologie:computation-observer', 'coffeescript', 'reactive-var', 'tinytest']);
	api.addFiles('computation-observer-tests.coffee');
});
