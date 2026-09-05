angular.module('vaporcito.core')
    .filter('binary', function () {
        return function (input) {
            return unitPrefixed(input, true);
        };
    });
