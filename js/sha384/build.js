const esbuild = require('esbuild');

const build = () => {
  esbuild.build({
    entryPoints: ['./src/index.ts'],
    outfile: 'dist/sha384.js',
    bundle: true,
    minify: true,
    treeShaking: true,
    globalName: 'SHA384',
  });
};

build();
