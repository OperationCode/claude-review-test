'use strict';

const isNumber = require('is-number');

// Returns true when value is a whole number that divides by two.
function isEven(value) {
  if (!isNumber(value)) {
    throw new TypeError('expected a number');
  }
  const n = Number(value);
  if (!Number.isInteger(n)) {
    throw new TypeError('expected an integer');
  }
  return n % 2 === 0;
}

module.exports = isEven;
