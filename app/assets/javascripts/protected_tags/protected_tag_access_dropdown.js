/* eslint-disable arrow-parens, no-param-reassign, object-shorthand, no-else-return, comma-dangle, max-len */

(global => {
  global.gl = global.gl || {};

  gl.ProtectedTagAccessDropdown = class {
    constructor(options) {
      const { $dropdown, data, onSelect } = options;

      $dropdown.glDropdown({
        data: data,
        selectable: true,
        inputId: $dropdown.data('input-id'),
        fieldName: $dropdown.data('field-name'),
        toggleLabel(item, el) {
          if (el.is('.is-active')) {
            return item.text;
          } else {
            return 'Select';
          }
        },
        clicked(item, $el, e) {
          e.preventDefault();
          onSelect();
        }
      });
    }
  };
})(window);
