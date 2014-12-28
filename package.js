Package.describe({
	name:    'mologie:computation-observer',
	summary: 'LiveQuery for arbitrary reactive computations',
	version: '0.0.1',
	git:     'https://github.com/mologie/meteor-computation-observer'
});

Package.onUse(function(api) {
	api.versionsFrom('1.0');
	api.use(['coffeescript', 'underscore'], 'client');
	api.addFiles('computation-observer.coffee', 'client');
	api.export('ComputationObserver', 'client');
});
