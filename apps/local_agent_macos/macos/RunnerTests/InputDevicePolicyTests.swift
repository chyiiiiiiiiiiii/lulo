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

  func testHeadphoneOutputNeedsNoEchoCanceller() {
    // With the far end delivered into the user's ears there is no echo
    // path to cancel, and the voice-processing unit is exactly what fights
    // Bluetooth routes (-10875 on every other engine start). Skip it.
    XCTAssertTrue(
      InputDevicePolicy.skipsEchoCancellation(
        outputTransport: kAudioDeviceTransportTypeBluetooth
      )
    )
    XCTAssertTrue(
      InputDevicePolicy.skipsEchoCancellation(
        outputTransport: kAudioDeviceTransportTypeBluetoothLE
      )
    )
  }

  func testASpeakerOutputKeepsTheCanceller() {
    // Anything that can put the agent's voice into the room needs the
    // canceller to keep it out of the microphone.
    for transport in [
      kAudioDeviceTransportTypeBuiltIn,
      kAudioDeviceTransportTypeUSB,
      kAudioDeviceTransportTypeHDMI,
      kAudioDeviceTransportTypeAggregate,
      kAudioDeviceTransportTypeVirtual,
      kAudioDeviceTransportTypeUnknown,
    ] {
      XCTAssertFalse(
        InputDevicePolicy.skipsEchoCancellation(outputTransport: transport),
        "transport \(transport) can reach the room and needs the canceller"
      )
    }
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
