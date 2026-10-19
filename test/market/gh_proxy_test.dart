// The gh-proxy URL builder. Pure logic, NO network.
//
// Every case here is derived from the C engine's `sys.gh_proxy`
// (`native/engine/tp_sysinfo_win.c:665`), which is the unified behaviour both
// original call sites (`lib/update.c:20-26` and `src/market_dialog.c:37-42`)
// are folded into.
//
// The `inChina` decision is a parameter throughout. Nothing in this file
// touches the network, which is the Phase 10 acceptance criterion
// ("URL 构造器单测，不打网络").

import 'package:taskpin/core/market/gh_proxy.dart';
import 'package:test/test.dart';

void main() {
  group('rewriteGithubUrl', () {
    test('not in China: the URL is returned unchanged', () {
      const String url = 'https://raw.githubusercontent.com/bestK/taskpin/master/version.txt';
      expect(rewriteGithubUrl(url, inChina: false), url);
    });

    test('in China: github.com is prefixed', () {
      expect(
        rewriteGithubUrl('https://github.com/bestK/taskpin', inChina: true),
        'https://gh-proxy.com/https://github.com/bestK/taskpin',
      );
    });

    test('in China: raw.githubusercontent.com is prefixed', () {
      expect(
        rewriteGithubUrl(
          'https://raw.githubusercontent.com/bestK/taskpin/master/manifest.json',
          inChina: true,
        ),
        'https://gh-proxy.com/https://raw.githubusercontent.com/bestK/taskpin/master/manifest.json',
      );
    });

    test('in China: api.github.com is prefixed', () {
      // "github" covers all three hosts without enumerating them.
      expect(
        rewriteGithubUrl('https://api.github.com/repos/bestK/taskpin/contents/', inChina: true),
        'https://gh-proxy.com/https://api.github.com/repos/bestK/taskpin/contents/',
      );
    });

    test('in China: a non-GitHub host is NOT prefixed', () {
      // gh-proxy.com can only fetch from GitHub, so prefixing anything else
      // produces a URL that cannot resolve.
      const String url = 'https://api.ip.sb/geoip';
      expect(rewriteGithubUrl(url, inChina: true), url);
      expect(rewriteGithubUrl('https://gitlab.com/x/y', inChina: true),
          'https://gitlab.com/x/y');
      expect(rewriteGithubUrl('https://mirror.example.org/file.lua', inChina: true),
          'https://mirror.example.org/file.lua');
    });

    test('the HOST is what is tested, not the path', () {
      // `github` in the path of a non-GitHub host must not trigger the proxy.
      // `l_sys_gh_proxy` slices host = between "://" and the next "/", so
      // `example.com/github` has host `example.com` and is left alone.
      const String url = 'https://example.com/github';
      expect(rewriteGithubUrl(url, inChina: true), url);
    });

    test('an already-proxied URL is not wrapped twice', () {
      const String url = 'https://gh-proxy.com/https://github.com/bestK/taskpin';
      expect(rewriteGithubUrl(url, inChina: true), url);
    });

    test('a host that merely contains "github" as a substring still matches', () {
      // The C test is `strstr(host_buf, "github")`, a substring search. An
      // attacker-controlled lookalike host would be proxied too; that is the
      // existing behaviour and gh-proxy would simply fail to fetch it.
      expect(
        rewriteGithubUrl('https://notgithub.example.com/x', inChina: true),
        'https://gh-proxy.com/https://notgithub.example.com/x',
      );
    });

    test('a malformed URL is returned unchanged rather than throwing', () {
      expect(rewriteGithubUrl('', inChina: true), '');
      expect(rewriteGithubUrl('github.com/x/y', inChina: true),
          'https://gh-proxy.com/github.com/x/y',
          reason: 'no scheme: the whole string is treated as the host');
      expect(rewriteGithubUrl('https://', inChina: true), 'https://');
    });

    test('a URL with no path after the host is still handled', () {
      expect(
        rewriteGithubUrl('https://github.com', inChina: true),
        'https://gh-proxy.com/https://github.com',
      );
    });
  });

  group('githubPath', () {
    test('builds a github.com URL when not in China', () {
      expect(
        githubPath('bestK/taskpin/raw/master/version.txt', inChina: false),
        'https://github.com/bestK/taskpin/raw/master/version.txt',
      );
    });

    test('builds the proxied form when in China', () {
      // The exact shape `lib/update.c:20-26`'s `gh_url` produces.
      expect(
        githubPath('bestK/taskpin/raw/master/version.txt', inChina: true),
        'https://gh-proxy.com/https://github.com/bestK/taskpin/raw/master/version.txt',
      );
    });

    test('tolerates a leading slash', () {
      expect(githubPath('/bestK/taskpin', inChina: false),
          'https://github.com/bestK/taskpin');
    });
  });

  group('rawGithubPath', () {
    test('builds the market manifest URL', () {
      // `mkt_build_raw_url`, src/market_dialog.c:37-42.
      expect(
        rawGithubPath('bestK/taskpin-plugins/master/manifest.json', inChina: false),
        'https://raw.githubusercontent.com/bestK/taskpin-plugins/master/manifest.json',
      );
      expect(
        rawGithubPath('bestK/taskpin-plugins/master/manifest.json', inChina: true),
        'https://gh-proxy.com/https://raw.githubusercontent.com/bestK/taskpin-plugins/master/manifest.json',
      );
    });
  });

  group('apiGithubPath', () {
    test('builds the contents-API URL', () {
      expect(
        apiGithubPath('repos/bestK/taskpin/contents/', inChina: false),
        'https://api.github.com/repos/bestK/taskpin/contents/',
      );
    });

    test('proxies the API host too, unlike the old market dialog', () {
      // Deliberate divergence: `src/market_dialog.c:126` left api.github.com
      // unproxied, but `lib/update.c:28-36` (`gh_api_get`) proxies it and
      // `sys.gh_proxy`'s rule is "any host containing github".
      expect(
        apiGithubPath('repos/bestK/taskpin/contents/', inChina: true),
        'https://gh-proxy.com/https://api.github.com/repos/bestK/taskpin/contents/',
      );
    });
  });
}
