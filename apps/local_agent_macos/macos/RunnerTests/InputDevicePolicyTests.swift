import CoreAudio
import XCTest

@testable import Lulo

final class InputDevicePolicyTests: XCTestCase {
  func testABluetoothMicrophoneIsDeclined() {
    // AirPods put a 24kHz telephony microphone under a voice-processing
    // engine that receives only zeros from it — worn headphones also mean
    // there is no echo path, so the built-in microphone is strictly better.
    XCTAssertTrue(
      InputDevicePolicy.pinsBuiltInMicrophone(
        transport: kAudioDeviceTransportTypeBluetooth
      )
    )
    XCTAssertTrue(
      InputDevicePolicy.pinsBuiltInMicrophone(
        transport: kAudioDeviceTransportTypeBluetoothLE
      )
    )
  }

  func testAMicrophoneSomeoneChoseIsRespected() {
    // A USB or built-in default input is a working choice, possibly a
    // deliberate one. Only the transport that delivers silence is refused.
    for transport in [
      kAudioDeviceTransportTypeBuiltIn,
      kAudioDeviceTransportTypeUSB,
      kAudioDeviceTransportTypeAggregate,
      kAudioDeviceTransportTypeVirtual,
      kAudioDeviceTransportTypeUnknown,
    ] {
      XCTAssertFalse(
        InputDevicePolicy.pinsBuiltInMicrophone(transport: transport),
        "transport \(transport) should keep the user's default input"
      )
    }
  }
}
