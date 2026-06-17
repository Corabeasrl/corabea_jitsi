config.defaultLogoUrl = 'https://meet.corabea.it/images/corabea-logo.png';

config.prejoinConfig = {
    enabled: true,
    hideDisplayName: false
};

config.bridgeChannel = {
    preferSctp: false
};

config.videoQuality = config.videoQuality || {};
config.videoQuality.maxBitratesVideo = {
    low: 300000,
    standard: 800000,
    high: 2500000,
    fullHd: 4000000
};
