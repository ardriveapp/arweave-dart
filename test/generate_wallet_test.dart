import 'package:arweave/arweave.dart';
import 'package:test/test.dart';

void main() {
  group('wallet class', () {
    test('generate a wallet from mnemonics', () async {
      const String mnemonics =
          'shrimp pony traffic photo favorite plastic fancy gadget february surge surface innocent';

      var wallet = await Wallet.generate(seed: mnemonics);
      expect(
        await wallet.getAddress(),
        '0nYC9uPt61tUhVKH_rqbGLmfA5zPP1Vv263nDSyxzds',
      );
    });
  });
}
