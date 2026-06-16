config.defaultLogoUrl = 'https://meet.corabea.it/images/corabea-logo.png';

config.prejoinConfig = {
    enabled: true,
    hideDisplayName: false
};

config.bridgeChannel = {
    preferSctp: false
};

config.resolution = 1080;
config.constraints = {
    video: {
        height: { ideal: 1080, max: 1080, min: 180 },
        width:  { ideal: 1920, max: 1920, min: 320 },
    }
};

config.videoQuality = config.videoQuality || {};
config.videoQuality.codecPreferenceOrder = ["VP8", "VP9", "H264", "AV1"];
config.videoQuality.mobileCodecPreferenceOrder = ["VP8", "H264", "VP9", "AV1"];
config.p2p = config.p2p || {};
config.p2p.codecPreferenceOrder = ["VP8", "H264", "VP9", "AV1"];
