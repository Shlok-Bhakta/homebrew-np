class NpAppwatch < Formula
  desc "Switches the NP Band Remote dongle's gesture profile with the app in front"
  homepage "https://github.com/Shlok-Bhakta/homebrew-np"
  url "https://github.com/Shlok-Bhakta/homebrew-np/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "8bb7fbe9272d57e6b144b47c803a03746659b356553423b1e878eb17b61f952d"
  license "MIT"
  head "https://github.com/Shlok-Bhakta/homebrew-np.git", branch: "main"

  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/np-appwatch"
  end

  service do
    run [opt_bin/"np-appwatch"]
    keep_alive true
    process_type :interactive
    log_path var/"log/np-appwatch.log"
    error_log_path var/"log/np-appwatch.log"
  end

  def caveats
    <<~EOS
      Start it now and at every login:
        brew services start np-appwatch
      macOS asks once to let np-appwatch use Bluetooth: allow it.
      Profiles pick apps by bundle id ("apps" in the dongle's profile file); `np-appwatch front`
      prints the front app's.
      To buzz the band when GitHub Copilot finishes, asks something or fails:
        np-appwatch copilot install
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/np-appwatch --version")
  end
end
