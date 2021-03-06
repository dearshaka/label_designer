module.exports = {
  "extends": "airbnb-base",
  "plugins": [
    "import"
  ],
  "parserOptions": {
    "sourceType": 'script',
    "ecmaFeatures": {
      "impliedStrict": true
    }
  },
  "rules": {
    "no-param-reassign": [ "error", { "props": false } ],
    // "no-console": [ 0 ],
    // "no-alert": [ 0 ],
    // "func-names": [ 0 ],
    // "max-len": [ 0 ],
  },
  "env": {
    "browser": true,
    "jquery": true,
  },
  "globals": {
    "_": false,
    "swal": false,
    "agGrid": false,
    "Jackbox": false,
    "Konva": false,
    "Selectr": false,
    "Sortable": false,
    "multi": false,
    "crossbeamsRmdScan": false,
    "crossbeamsDialogLevel1": false,
    "crossbeamsDialogLevel2": false,
    "crossbeamsGridStore": false,
    "crossbeamsUtils": false,
    "crossbeamsLocalStorage": false,
    "crossbeamsGridEvents": false
  }
};
