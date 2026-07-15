// wasm; the @(require) keeps it linked even though nothing calls it directly.
#+build wasm32
package yoga

@(require) import _ "src:polyfill"
