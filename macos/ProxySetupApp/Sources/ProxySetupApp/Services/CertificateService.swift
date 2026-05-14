import Foundation

struct CertificateService {
    static func renderOpenSSLConfig() -> String {
        """
        [req]
        default_bits = 2048
        prompt = no
        default_md = sha256
        req_extensions = req_ext
        distinguished_name = dn

        [dn]
        CN = localhost

        [req_ext]
        subjectAltName = @alt_names

        [alt_names]
        IP.1 = 127.0.0.1
        IP.2 = ::1
        DNS.1 = localhost
        """
    }

    func generationCommands(certsDirectory: URL) -> [[String]] {
        let dir = certsDirectory.path
        return [
            ["openssl", "genrsa", "-out", "\(dir)/ca.key", "2048"],
            [
                "openssl",
                "req",
                "-x509",
                "-new",
                "-nodes",
                "-key",
                "\(dir)/ca.key",
                "-sha256",
                "-days",
                "3650",
                "-out",
                "\(dir)/ca.crt",
                "-subj",
                "/CN=CJ Local Proxy CA",
            ],
            ["openssl", "genrsa", "-out", "\(dir)/server.key", "2048"],
            [
                "openssl",
                "req",
                "-new",
                "-key",
                "\(dir)/server.key",
                "-out",
                "\(dir)/server.csr",
                "-config",
                "\(dir)/openssl-server.cnf",
            ],
            [
                "openssl",
                "x509",
                "-req",
                "-in",
                "\(dir)/server.csr",
                "-CA",
                "\(dir)/ca.crt",
                "-CAkey",
                "\(dir)/ca.key",
                "-CAcreateserial",
                "-out",
                "\(dir)/server.crt",
                "-days",
                "825",
                "-sha256",
                "-extensions",
                "req_ext",
                "-extfile",
                "\(dir)/openssl-server.cnf",
            ],
        ]
    }
}
