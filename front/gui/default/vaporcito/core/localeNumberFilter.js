angular.module('vaporcito.core')
    .filter('localeNumber', function () {
        return function (input) {
            return input.toLocaleString();
        };
    });
