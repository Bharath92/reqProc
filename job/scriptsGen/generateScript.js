'use strict';

var self = generateScript;
module.exports = self;

var path = require('path');
var fs = require('fs-extra');

var generateScriptFromTemplate = require('./generateScriptFromTemplate.js');

function generateScript(externalBag, callback) {
  var bag = {
    script: externalBag.script,
    onSuccess: externalBag.onSuccess,
    onFailure: externalBag.onFailure,
    always: externalBag.always,
    taskIndex: externalBag.taskIndex,
    taskScriptFileName: externalBag.taskScriptFileName,
    bootScriptFileName: externalBag.bootScriptFileName,
    name: externalBag.name,
    runtime: externalBag.runtime,
    buildScriptsDir: externalBag.buildScriptsDir,
    taskScript: '',
    bootScript: '',
    scriptFilePermissions: '755',
    buildRootDir: externalBag.buildRootDir,
    buildJobId: externalBag.buildJobId,
    commonEnvs: externalBag.commonEnvs,
    shippableRuntimeEnvs: externalBag.shippableRuntimeEnvs,
    inDependencies: externalBag.inDependencies,
    buildStatusDir: externalBag.buildStatusDir,
    integrationInitScripts: [],
    integrationCleanupScripts: []
  };
  bag.defaultDockerEnvs = '';

  bag.who = util.format('%s|job|%s', msName, self.name);
  logger.info(bag.who, 'Inside');

  if (global.config.shippableNodeOperatingSystem === 'WindowsServer_2016') {
    bag.taskTemplateFileName = 'task.ps1';
    bag.scriptHeaderFileName = 'header.ps1';
    bag.bootTemplateFileName = 'boot.ps1';
    bag.envTemplateFileName = 'envs.ps1';
  } else {
    bag.taskTemplateFileName = 'task.sh';
    bag.scriptHeaderFileName = 'header.sh';
    bag.bootTemplateFileName = 'boot.sh';
    bag.envTemplateFileName = 'envs.sh';
  }

  async.series([
      _checkInputParams.bind(null, bag),
      _getScriptHeader.bind(null, bag),
      _generateEnvScriptFromTemplate.bind(null, bag),
      _addInDependencyScripts.bind(null, bag),
      _generateTaskScriptFromTemplate.bind(null, bag),
      _createTaskScriptFile.bind(null, bag),
      _getContainerBootScript.bind(null, bag),
      _createBootScript.bind(null, bag)
    ],
    function (err) {
      var result;
      if (err) {
        logger.error(bag.who,
          util.format('Failed to create script'));
      } else {
        logger.info(bag.who, 'Successfully created script');
        result = {};

        if (bag.runtime.container)
          result.scriptFileName = bag.bootScriptFileName;
        else
          result.scriptFileName = bag.taskScriptFileName;
      }
      return callback(err, result);
    }
  );
}

function _checkInputParams(bag, next) {
  var who = bag.who + '|' + _checkInputParams.name;
  logger.verbose(who, 'Inside');

  return next();
}

function _getScriptHeader(bag, next) {
  var who = bag.who + '|' + _getScriptHeader.name;
  logger.verbose(who, 'Inside');

  var headerFile = path.join(global.config.execTemplatesDir, 'job',
    bag.scriptHeaderFileName);

  fs.readFile(headerFile, 'utf8',
    function (err, header) {
      if (err) {
        logger.error(util.format('%s, Failed to read file: %s ' +
          'with err: %s', who, headerFile, err));
        return next(err);
      }
      bag.taskScript = bag.taskScript.concat(header);
      bag.bootScript = bag.bootScript.concat(header);
      return next();
    }
  );
}

function _generateEnvScriptFromTemplate(bag, next) {
  var who = bag.who + '|' + _generateEnvScriptFromTemplate.name;
  logger.verbose(who, 'Inside');

  var templateBag = {
    filePath: path.join(global.config.execTemplatesDir, 'job',
      bag.envTemplateFileName),
    object: {
      commonEnvs: bag.commonEnvs,
      taskEnvs: bag.runtime.options.env,
      shippableRuntimeEnvs: bag.shippableRuntimeEnvs,
    }
  };

  generateScriptFromTemplate(templateBag,
    function (err, resultBag) {
      if (err) {
        logger.error(util.format('%s, Generate script from template failed ' +
          'with err: %s', who, err));
        return next(err);
      }
      bag.taskScript = bag.taskScript.concat(resultBag.script);
      bag.bootScript = bag.bootScript.concat(resultBag.script);
      return next();
    }
  );
}

function _addInDependencyScripts(bag, next) {
  var who = bag.who + '|' + _addInDependencyScripts.name;
  logger.verbose(who, 'Inside');

  _.each(bag.inDependencies,
    function (inDependency) {
      if (!_.isEmpty(inDependency.integrationInitScriptCommand))
        bag.integrationInitScripts.push(
          inDependency.integrationInitScriptCommand);
      if (!_.isEmpty(inDependency.integrationCleanupScriptCommand))
        bag.integrationCleanupScripts.push(
          inDependency.integrationCleanupScriptCommand);
    }
  );

  return next();
}

function _generateTaskScriptFromTemplate(bag, next) {
  var who = bag.who + '|' + _generateTaskScriptFromTemplate.name;
  logger.verbose(who, 'Inside');

  var templateBag = {
    filePath: path.join(global.config.execTemplatesDir, 'job',
      bag.taskTemplateFileName),
    object: {
      script: bag.script,
      onSuccess: bag.onSuccess,
      onFailure: bag.onFailure,
      always: bag.always,
      integrationInitScripts: bag.integrationInitScripts,
      integrationCleanupScripts: bag.integrationCleanupScripts
    }
  };

  generateScriptFromTemplate(templateBag,
    function (err, resultBag) {
      if (err) {
        logger.error(util.format('%s, Generate script from template failed ' +
          'with err: %s', who, err));
        return next(err);
      }
      bag.taskScript = bag.taskScript.concat(resultBag.script);
      return next();
    }
  );
}

function _createTaskScriptFile(bag, next) {
  var who = bag.who + '|' + _createTaskScriptFile.name;
  logger.verbose(who, 'Inside');

  var scriptFilePath = path.join(bag.buildScriptsDir, bag.taskScriptFileName);

  __writeScriptFile(bag.taskScript, scriptFilePath, bag.scriptFilePermissions,
    function (err) {
      if (err) {
        logger.error(util.format('%s, Failed to write file: %s ' +
          'with err: %s', who, scriptFilePath, err));
        return next(err);
      }
      return next();
    }
  );
}

function _getContainerBootScript(bag, next) {
  if (!bag.runtime.container) return next();

  var who = bag.who + '|' + _getContainerBootScript.name;
  logger.verbose(who, 'Inside');

  var bootScriptFilePath = path.join(global.config.execTemplatesDir, 'job',
    bag.bootTemplateFileName);

  fs.readFile(bootScriptFilePath, 'utf8',
    function (err, bootScript) {
      if (err) {
        logger.error(util.format('%s, Failed to read file: %s ' +
          'with err: %s', who, bootScriptFilePath, err));
        return next(err);
      }
      bag.bootScript = bag.bootScript.concat(bootScript);
      return next();
    }
  );
}

function _createBootScript(bag, next) {
  if (!bag.runtime.container) return next();

  var who = bag.who + '|' + _createBootScript.name;
  logger.verbose(who, 'Inside');

  var scriptFilePath = path.join(bag.buildScriptsDir, bag.bootScriptFileName);

  __writeScriptFile(bag.bootScript, scriptFilePath, bag.scriptFilePermissions,
    function (err) {
      if (err) {
        logger.error(util.format('%s, Failed to write file: %s ' +
          'with err: %s', who, scriptFilePath, err));
        return next(err);
      }
      return next();
    }
  );
}

function __writeScriptFile(script, scriptFilePath, scriptFilePermissions,
  callback) {
  fs.writeFile(scriptFilePath, script,
    function (err) {
      if (err) {
        logger.error(util.format('Failed to write file: %s ' +
          'with err: %s', scriptFilePath, err));
        return callback(err);
      }
      fs.chmodSync(scriptFilePath, scriptFilePermissions);
      return callback();
    }
  );
}
