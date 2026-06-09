interfaceConfig.APP_NAME = 'Corabea Meet';
interfaceConfig.NATIVE_APP_NAME = 'Corabea Meet';
interfaceConfig.PROVIDER_NAME = 'Corabea';

interfaceConfig.DEFAULT_WELCOME_PAGE_LOGO_URL = 'images/corabea-logo.png';
interfaceConfig.SHOW_JITSI_WATERMARK = true;
interfaceConfig.JITSI_WATERMARK_LINK = 'https://corabea.it';

interfaceConfig.SHOW_BRAND_WATERMARK = false;
interfaceConfig.SHOW_POWERED_BY = false;
interfaceConfig.SHOW_PROMOTIONAL_CLOSE_PAGE = false;
interfaceConfig.HIDE_DEEP_LINKING_LOGO = true;

(function enlargeCorabeaWatermark() {
    var css =
        '.watermark.leftwatermark{width:150px !important;height:68px !important;}' +
        '.leftwatermark{max-width:150px !important;max-height:68px !important;}';
    function inject() {
        var style = document.createElement('style');
        style.setAttribute('data-corabea', 'watermark');
        style.textContent = css;
        (document.head || document.documentElement).appendChild(style);
    }
    if (document.head) {
        inject();
    } else {
        document.addEventListener('DOMContentLoaded', inject);
    }
})();

(function fixCorabeaTabTitle() {
    function desiredTitle() {
        try {
            var m = (window.location.hash || '').match(/config\.subject=([^&]+)/);
            if (m) {
                var s = decodeURIComponent(m[1]).replace(/^"+|"+$/g, '').trim();
                if (s) {
                    return s + ' | ' + interfaceConfig.APP_NAME;
                }
            }
        } catch (e) { /* ignore */ }
        return interfaceConfig.APP_NAME;
    }

    var want = desiredTitle();
    function enforce() {
        if (document.title !== want) {
            document.title = want;
        }
    }
    enforce();

    function watch() {
        var titleEl = document.querySelector('title');
        if (titleEl) {
            new MutationObserver(enforce).observe(titleEl, { childList: true });
        }
        setInterval(enforce, 1000);
    }
    if (document.querySelector('title')) {
        watch();
    } else {
        document.addEventListener('DOMContentLoaded', watch);
    }
})();

(function setCorabeaFavicon() {
    var HREF = 'images/corabea-logo.png?v=1';

    function apply() {
        var head = document.head || document.getElementsByTagName('head')[0];
        if (!head) {
            return;
        }

        var icon = document.querySelector('link[rel~="icon"]');
        if (!icon) {
            icon = document.createElement('link');
            icon.setAttribute('rel', 'icon');
            head.appendChild(icon);
        }
        icon.setAttribute('type', 'image/png');
        icon.setAttribute('href', HREF);

        var apple = document.querySelector('link[rel="apple-touch-icon"]');
        if (!apple) {
            apple = document.createElement('link');
            apple.setAttribute('rel', 'apple-touch-icon');
            head.appendChild(apple);
        }
        apple.setAttribute('href', HREF);
    }

    if (document.head) {
        apply();
    } else {
        document.addEventListener('DOMContentLoaded', apply);
    }
})();
