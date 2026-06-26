config.defaultLogoUrl = 'https://meet.corabea.it/images/corabea-logo.png';

config.prejoinConfig = {
    enabled: true,
    hideDisplayName: false
};

config.bridgeChannel = {
    preferSctp: false
};

config.enableOpusRed = true;

config.p2p = config.p2p || {};
config.p2p.enabled = false;
config.p2p.stunServers = [
    { urls: 'stun:meet.corabea.it:3478' }
];

config.videoQuality = config.videoQuality || {};
config.videoQuality.maxBitratesVideo = {
    VP8:  { low: 200000, standard: 800000, high: 2500000, fullHd: 4000000, ultraHd: 6000000 },
    VP9:  { low: 100000, standard: 600000, high: 2000000, fullHd: 3500000, ultraHd: 5000000 },
    AV1:  { low: 100000, standard: 500000, high: 1500000, fullHd: 3000000, ultraHd: 5000000 },
    H264: { low: 200000, standard: 800000, high: 2500000, fullHd: 4000000, ultraHd: 6000000 }
};
