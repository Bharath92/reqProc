'use strict';
var self = inStep;
module.exports = self;

var fs = require('fs-extra');
var path = require('path');

function inStep(params, callback) {
  var bag = {
    resBody: {},
    dependency: params.dependency,
    buildInDir: params.rootDir,
    builderApiAdapter: params.builderApiAdapter,
    consoleAdapter: params.consoleAdapter
  };

  bag.who = util.format('%s|job|handlers|resources|params|%s',
    msName, self.name);
  logger.verbose(bag.who, 'Starting');

  bag.paramsPath =
    path.join(bag.buildInDir, bag.dependency.name, 'params');

  async.series([
      _checkInputParams.bind(null, bag),
      _extractParams.bind(null, bag),
      _writeParams.bind(null, bag)
    ],
    function (err) {
      logger.verbose(bag.who, 'Completed');
      return callback(err, bag.resBody);
    }
  );
}

function _checkInputParams(bag, next) {
  var who = bag.who + '|' + _checkInputParams.name;
  logger.debug(who, 'Inside');

  var consoleErrors = [];

  if (!bag.dependency.version.propertyBag.params)
    consoleErrors.push(
      util.format('%s is missing: dependency.version.propertyBag.params', who)
    );

  if (consoleErrors.length > 0) {
    _.each(consoleErrors,
      function (e) {
        var msg = e;
        logger.error(bag.who, e);
        bag.consoleAdapter.publishMsg(msg);
      }
    );
    bag.consoleAdapter.closeCmd(false);
    return next(true);
  }

  bag.consoleAdapter.publishMsg('Successfully validated dependencies');
  return next();
}

function _extractParams(bag, next) {
  var who = bag.who + '|' + _extractParams.name;
  logger.debug(who, 'Inside');

  bag.extractedParams = '';
  _.each(bag.dependency.version.propertyBag.params,
    function (paramValue, paramKey) {
      if (paramKey === 'secure')
        bag.extractedParams += paramValue + '\n';
      else
        bag.extractedParams += util.format('%s=%s\n', paramKey, paramValue);
    }
  );
  bag.consoleAdapter.publishMsg('Successfully extracted params');

  return next();
}

function _writeParams(bag, next) {
  var who = bag.who + '|' + _writeParams.name;
  logger.debug(who, 'Inside');

  fs.outputFile(bag.paramsPath, bag.extractedParams,
    function(err) {
      return next(err);
    }
  );
}
