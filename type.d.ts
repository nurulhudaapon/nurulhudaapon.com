declare module "*.wasm" {
    /** Compiled Ziex WASI Binary */
    const module: WebAssembly.Module;
    export default module;
}

