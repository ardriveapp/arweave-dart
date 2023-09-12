import { createSHA384 } from 'hash-wasm';
declare function sha384Hash(data: Uint8Array): Promise<Uint8Array>;
export { createSHA384, sha384Hash, };
