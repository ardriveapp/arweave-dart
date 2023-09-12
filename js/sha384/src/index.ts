import { createSHA384, sha384 } from 'hash-wasm';

async function sha384Hash(data: Uint8Array): Promise<Uint8Array> {
	return hexToUint8Array(await sha384(data));
}

function hexToUint8Array(hexString: string): Uint8Array {
	const length = hexString.length / 2;
	const result = new Uint8Array(length);

	for (let i = 0; i < length; i++) {
		const byte = hexString.substr(i * 2, 2);
		result[i] = parseInt(byte, 16);
	}

	return result;
}

export {
	createSHA384,
	sha384Hash,
}
