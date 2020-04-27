var fs = require('fs'), path = require('path');
//Sets the preference on config.xml for using Swift 5

module.exports = function(context) {

    var configXML = path.join(context.opts.projectRoot, 'config.xml');
    
    if (fs.existsSync(configXML)) {
     
      fs.readFile(configXML, 'utf8', function (err,data) {
        
        if (err) {
          throw new Error('>>> Unable to read config.xml: ' + err);
        }
        
        var result = data;
        var shouldBeSaved = false;

        if (!data.includes('"UseSwiftLanguageVersion" value="5"')){
          shouldBeSaved = true;
          result = data.replace(/<platform name="ios">/g, '<platform name="ios">\n\t\t<preference name="UseSwiftLanguageVersion" value="5" />');
        } else {
          console.log(">>> config.xml was already modified <<<");
        }

        if (shouldBeSaved){
          fs.writeFile(configXML, result, 'utf8', function (err) {
          if (err) 
            {throw new Error('>>> Unable to write into config.xml: ' + err);}
          else 
            {console.log(">>> config.xml edited successfuly <<<");}
        });
        }

      });
    } else {
        throw new Error(">>> WARNING: config.xml was not found. The build phase may not finish successfuly");
    }
  }
