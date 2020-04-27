"use strict"

var path = require("path");
var fs = require("fs");

var utils = require("./utilities2");

var constants = {
  platforms: "platforms",
  android: {
    platform: "android",
    wwwFolder: "assets/www",
    firebaseFileExtension: ".json",
    soundFileName: "push_sound.wav",
    getSoundDestinationFolder: function() {
      return "platforms/android/res/raw";
    }
  },
  ios: {
    platform: "ios",
    wwwFolder: "www",
    firebaseFileExtension: ".plist",
    soundFileName: "push_sound.caf",
    getSoundDestinationFolder: function(context) {
      return "platforms/ios/" + utils.getAppName(context) + "/Resources";
    }
  },
  zipExtension: ".zip"
};

function handleError(errorMessage, defer) {
  console.log(errorMessage);
  defer.reject();
}

function getFilesFromPath(path) {
  return fs.readdirSync(path);
}

function createOrCheckIfFolderExists(path) {
  if (!fs.existsSync(path)) {
    fs.mkdirSync(path);
  }
}

function getResourcesFolderPath(context, platform, platformConfig) {
  var platformPath = path.join(context.opts.projectRoot, constants.platforms, platform);
  return path.join(platformPath, platformConfig.wwwFolder);
}

function getPlatformConfigs(platform) {
  if (platform === constants.android.platform) {
    return constants.android;
  } else if (platform === constants.ios.platform) {
    return constants.ios;
  }
}

function getZipFile(folder, zipFileName) {
  try {
    var files = getFilesFromPath(folder);
    for (var i = 0; i < files.length; i++) {
      if (files[i].endsWith(constants.zipExtension)) {
        var fileName = path.basename(files[i], constants.zipExtension);
        if (fileName === zipFileName) {
          return path.join(folder, files[i]);
        }
      }
    }
  } catch (e) {
    console.log(e);
    return;
  }
}

function getAppId(context) {
  var cordovaAbove8 = isCordovaAbove(context, 8);
  var et;
  if (cordovaAbove8) {
    et = require('elementtree');
  } else {
    et = context.requireCordovaModule('elementtree');
  }

  var config_xml = path.join(context.opts.projectRoot, 'config.xml');
  var data = fs.readFileSync(config_xml).toString();
  var etree = et.parse(data);
  return etree.getroot().attrib.id;
}

function isCordovaAbove(context, version) {
  var cordovaVersion = context.opts.cordova.version;
  console.log(cordovaVersion);
  var sp = cordovaVersion.split('.');
  return parseInt(sp[0]) >= version;
}

function getAndroidTargetSdk(context) {
  var cordovaAbove8 = isCordovaAbove(context, 8);
  var et;
  if (cordovaAbove8) {
    et = require('elementtree');
  } else {
    et = context.requireCordovaModule('elementtree');
  }

  var androidManifestPath1 = path.join("platforms", "android", "AndroidManifest.xml");
  var androidManifestPath2 = path.join("platforms", "android", "app", "src", "main", "AndroidManifest.xml");

  var data;
  if (checkIfFolderExists(androidManifestPath1)) {
    data = fs.readFileSync(androidManifestPath1).toString();
  } else if (checkIfFolderExists(androidManifestPath2)){
    data = fs.readFileSync(androidManifestPath2).toString();
  } else {
    return;
  }

  var etree = et.parse(data);
  var sdk = etree.findall('./uses-sdk')[0].get('android:targetSdkVersion');
  return parseInt(sdk);
}

function copyFromSourceToDestPath(defer, sourcePath, destPath) {
  console.log(sourcePath)
  console.log(destPath)
  fs.copyFileSync(sourcePath, destPath)
}

function checkIfFolderExists(path) {
  return fs.existsSync(path);
}

module.exports = {
  isCordovaAbove,
  handleError,
  getZipFile,
  getResourcesFolderPath,
  getPlatformConfigs,
  getAppId,
  copyFromSourceToDestPath,
  getFilesFromPath,
  createOrCheckIfFolderExists,
  checkIfFolderExists,
  getAndroidTargetSdk
};