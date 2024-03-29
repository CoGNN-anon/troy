#include "../../app/LinearHelper.cuh"
#include "sys/time.h"
#include <iomanip>

using namespace troyn;
using namespace std;

class Timer {
public:
    std::vector<timeval> times;
    std::vector<double> accumulated; // ms
    std::vector<std::string> names;
    Timer() {}
    long registerTimer(std::string name = "") {
        times.push_back(timeval()); 
        accumulated.push_back(0);
        int ret = times.size() - 1;
        names.push_back(name);
        return ret;
    }
    void tick(long i = 0) {
        if (times.size() < 1) registerTimer();
        assert(i < times.size());
        gettimeofday(&times[i], 0);
    }
    double tock(long i = 0) {
        assert(i < times.size());
        timeval s; gettimeofday(&s, 0);
        auto timeElapsed = (s.tv_sec - times[i].tv_sec) * 1000.0;
        timeElapsed += (s.tv_usec - times[i].tv_usec) / 1000.0;
        accumulated[i] += timeElapsed;
        return accumulated[i];
    }
    
    void clear() {
        times.clear();
        accumulated.clear();
        names.clear();
    }

    std::map<std::string, double> gather(double divisor = 1) {
        std::map<std::string, double> p;
        for (long i=0; i<times.size(); i++) {
            p[names[i]] = accumulated[i] / divisor;
        }
        clear();
        return p;
    }
};

class LinearTest {

    Encryptor* encryptor;
    Decryptor* decryptor;
    Evaluator* evaluator;
    SEALContext* context;
    RelinKeys rlk;
    PublicKey pk;
    GaloisKeys gk;
    GaloisKeys autok;
    KeyGenerator* keygen;
    EncryptionParameters parms;

    vector<ParmsID> parmIDs;

    BatchEncoder* encoder;
    size_t slotCount;
    int dataBound;
    double delta;
    uint64_t modulus;

public:

    // Plaintext decryptp(const Ciphertext& c) {
    //     Plaintext p; decryptor->decrypt(c, p);
    //     return p;
    // }

    // vector<double> decrypt(const Plaintext& p) {
    //     vector<double> ret; encoder->decodePolynomial(p, ret);
    //     return ret;
    // }

    // vector<double> decrypt(const Ciphertext& c) {
    //     return decrypt(decryptp(c));
    // }

    void printVector(const vector<double>& r, bool full = false) {
        std::cout << "[";
        for (size_t i = 0; i < r.size(); i++) {
            if (r.size() > 8 && !full && i == 4) {
                std::cout << " ...";
                i = r.size() - 4;
            }
            if (i!=0) std::cout << ", ";
            std::cout << std::setprecision(1) << std::fixed << r[i];
        }
        std::cout << "]" << std::endl;
    }

    void printVector(const vector<double>& r, size_t terms) {
        std::cout << "[";
        for (size_t i = 0; i < std::min(r.size(), terms); i++) {
            if (i!=0) std::cout << ", ";
            std::cout << std::setprecision(1) << std::fixed << r[i];
        }
        std::cout << "]" << std::endl;
    }

    void printVector(const vector<uint64_t>& r) {
        std::cout << "[";
        for (size_t i = 0; i < r.size(); i++) {
            if (i!=0) std::cout << ", ";
            std::cout << r[i];
        }
        std::cout << "]" << std::endl;
    }

    void printVector(const vector<uint64_t>& r, size_t terms) {
        std::cout << "[";
        for (size_t i = 0; i < std::min(r.size(), terms); i++) {
            if (i!=0) std::cout << ", ";
            std::cout << r[i];
        }
        std::cout << "]" << std::endl;
    }

    vector<double> randomRealVector(size_t count = 0, int data_bound = 0) {
        if (count == 0) count = slotCount;
        if (data_bound == 0) data_bound = dataBound;
        vector<double> input(count, 0.0);
        for (size_t i = 0; i < count; i++)
        {
            input[i] = (static_cast<double>(rand()) / RAND_MAX - 0.5) * 2 * data_bound;
        }
        return input;
    }

    vector<uint64_t> randomVector(size_t count = 0, uint64_t data_bound = 0) {
        if (count == 0) count = slotCount;
        if (data_bound == 0) data_bound = dataBound;
        vector<uint64_t> input(count, 0.0);
        for (size_t i = 0; i < count; i++)
        {
            input[i] = ((((uint64_t)(rand())) << 32) + ((uint64_t)(rand()))) % data_bound;
        }
        return input;
    }

    void printTimer(std::map<std::string, double> r) {
        for (auto& p: r) {
            std::cout << std::setw(25) << std::right << p.first << ":";
            std::cout << std::setw(10) << std::right << std::fixed << std::setprecision(3)
                << p.second << std::endl;
        }
    }

    LinearTest(size_t polyModulusDegree, vector<int> qs, int dataBound, uint64_t plainModulus, uint64_t scale) {
        KernelProvider::initialize();
        slotCount = polyModulusDegree;
        this->dataBound = dataBound;
        this->delta = scale;
        parms = EncryptionParameters(SchemeType::bfv);
        parms.setPolyModulusDegree(polyModulusDegree);
        parms.setPlainModulus(plainModulus);
        modulus = plainModulus;
        parms.setCoeffModulus(CoeffModulus::Create(polyModulusDegree, qs));
        context = new SEALContext(parms, true, SecurityLevel::none);
        keygen = new KeyGenerator(*context);
        keygen->createPublicKey(pk);
        keygen->createRelinKeys(rlk);
        keygen->createGaloisKeys(gk);
        autok = keygen->createAutomorphismKeys();
        encoder = new BatchEncoder(*context);
        encryptor = new Encryptor(*context, pk);
        encryptor->setSecretKey(keygen->secretKey());
        decryptor = new Decryptor(*context, keygen->secretKey());
        evaluator = new Evaluator(*context);

        parmIDs.clear();
        std::shared_ptr<const SEALContext::ContextDataCuda> cd = context->firstContextData();
        while (cd) {
            parmIDs.push_back(cd->parmsID());
            cd = cd->nextContextData();
        }
    }

    vector<uint64_t> getUint64(const vector<double>& r) {
        uint64_t modulus = context->firstContextData()->parms().plainModulus().value();
        vector<uint64_t> x(r.size());
        int64_t half = modulus >> 1;
        for (size_t i = 0; i < r.size(); i++) {
            int64_t xi = static_cast<int64_t>(r[i] * delta);
            assert((xi < half) && (xi > -half));
            x[i] = (xi < 0) ? (modulus + xi) : xi;
        }
        return x;
    }

    vector<double> getDouble(const vector<uint64_t>& r, double m = 0) {
        uint64_t modulus = context->firstContextData()->parms().plainModulus().value();
        vector<double> x(r.size());
        int64_t half = modulus >> 1;
        if (m==0) m = delta;
        for (size_t i = 0; i < r.size(); i++) {
            assert(r[i] < modulus);
            if (r[i] > half) x[i] = -(static_cast<double>(modulus - r[i])) / m;
            else x[i] = static_cast<double>(r[i]) / m;
        }
        return x;
    }

    // void testMatmul(size_t batchSize, size_t inputDims, size_t outputDims) {
        
    //     // generate data
    //     auto weights = randomRealVector(inputDims * outputDims);
    //     auto x = randomRealVector(batchSize * inputDims);
    //     auto scaledX1 = getUint64(x);
        
    //     vector<uint64_t> scaledX2(scaledX1.size());
    //     for (size_t i = 0; i < scaledX2.size(); i++) {
    //         scaledX2[i] = rand() % modulus;
    //         scaledX1[i] = (scaledX1[i] + modulus - scaledX2[i]) % modulus;
    //     }

    //     auto lastParmsID = context->lastParmsID();

    //     // initialize helper
    //     LinearHelper::MatmulHelper helper(batchSize, inputDims, outputDims, slotCount);
    //     printf("Matmul helper created\n");
    //     auto encodedWeights = helper.encodeWeights(*encoder, getUint64(weights));
    //     printf("Weight encoded\n");
        

    //     // interaction
    //     auto x1Enc = helper.encryptInputs(*encryptor, *encoder, scaledX1);
    //     auto x2Enc = helper.encryptInputs(*encryptor, *encoder, scaledX2);
    //     // { // serialize
    //     //     ostringstream sout; xEnc.save(sout);
    //     //     auto p = sout.str(); std::cout << "xEnc length = " << p.size() << std::endl;
    //     //     istringstream sin(p); xEnc = LinearHelper::Cipher2d();
    //     //     xEnc.load(sin, *context);
    //     // }
    //     printf("x encoded\n");
    //     auto yEnc1 = helper.matmul(*evaluator, x1Enc, encodedWeights);  
    //     yEnc1.modSwitchToNext(*evaluator);
    //     auto yEnc2 = helper.matmul(*evaluator, x2Enc, encodedWeights);   
    //     yEnc2.modSwitchToNext(*evaluator);
    //     yEnc1.addInplace(*evaluator, yEnc2);
    //     // { // serialize
    //     //     ostringstream sout; helper.serializeOutputs(*evaluator, yEnc, sout);
    //     //     auto p = sout.str(); std::cout << "yEnc length = " << p.size() << std::endl;
    //     //     istringstream sin(p); 
    //     //     yEnc = helper.deserializeOutputs(*evaluator, sin);
    //     // }
    //     printf("Matmul done\n");

    //     // dec
    //     auto yDec = getDouble(helper.decryptOutputs(*encoder, *decryptor, yEnc1), delta*delta);
    //     printf("Decrypted\n");
        
    //     // plaintext computation
    //     vector<double> y(batchSize * outputDims, 0);
    //     for (size_t i = 0; i < batchSize; i++) {
    //         for (size_t j = 0; j < inputDims; j++) {
    //             for (size_t k = 0; k < outputDims; k++) {
    //                 y[i * outputDims + k] += x[i * inputDims + j] * weights[j * outputDims + k];
    //             }
    //         }
    //     }

    //     // comparison
    //     double diff = 0;
    //     double reldiff = 0;
    //     for (size_t i = 0; i < batchSize * outputDims; i++) {
    //         double d = std::abs(y[i] - yDec[i]);
    //         double reld = d / std::abs(y[i]);
    //         if (d > diff) diff = d;
    //         if (reld > reldiff) reldiff = reld;
    //     }
    //     std::cout << "Difference = " << diff << " relative = " << reldiff << std::endl;
        
    // }

    
    std::vector<uint64_t> plainMatMul(const std::vector<uint64_t>& A, const std::vector<uint64_t>& B, uint64_t mod, size_t dim0, size_t dim1, size_t dim2) {
        // plaintext computation
        std::vector<uint64_t> C(dim0 * dim2, 0);
        for (size_t i = 0; i < dim0; i++) {
            for (size_t j = 0; j < dim1; j++) {
                for (size_t k = 0; k < dim2; k++) {
                    C[i * dim2 + k] += A[i * dim1 + j] * B[j * dim2 + k];
                    C[i * dim2 + k] %= mod;      
                }
            }
        }        
        return C;
    }

    void test_ss_Encode(size_t dim) {
        
        auto mod = parms.plainModulus().value();
        auto A = randomVector(dim, mod);
        auto A_0 = randomVector(dim, mod);
        auto A_1 = std::vector<uint64_t>(dim, 0); 
        // for (int i = 0; i < dim; ++i) A_1[i] = (A[i] - A_0[i]) % mod; 
        Plaintext A_0_Encoded, A_Encoded;

        auto timer = Timer();
        auto t = timer.registerTimer("Matmul"); timer.tick(t);

        encoder->encodePolynomial(A_0, A_0_Encoded);
        encoder->encodePolynomial(A, A_Encoded);
        auto A_Enc = encryptor->encryptSymmetric(A_Encoded);
        Ciphertext A_1_Enc;
        evaluator->subPlain(A_Enc, A_0_Encoded, A_1_Enc);
        Plaintext A_1_Encoded;
        decryptor->decrypt(A_1_Enc, A_1_Encoded);
        encoder->decodePolynomial(A_1_Encoded, A_1);

        timer.tock(t);
        printTimer(timer.gather());

        // comparison
        uint64_t diff = 0;
        for (size_t i = 0; i < dim; i++) {
            uint64_t d = std::abs<long long>(A[i] - ((A_0[i] + (A_1[i] % mod)) % mod));
            if (d > diff) diff = d;
        }
        std::cout << "Difference = " << diff << std::endl;
        
    }

    void test_ss_MatmulInts(size_t dim0, size_t dim1, size_t dim2, bool packLwes) {
        
        auto mod = parms.plainModulus().value();
        auto A = randomVector(dim0 * dim1, mod);
        auto B = randomVector(dim1 * dim2, mod);

        auto A_0 = randomVector(dim0 * dim1, mod);
        auto A_1 = std::vector<uint64_t>(dim0 * dim1, 0); 
        for (int i = 0; i < dim0 * dim1; ++i) A_1[i] = (A[i] - A_0[i]) % mod; 
        auto B_0 = randomVector(dim1 * dim2, mod);
        auto B_1 = std::vector<uint64_t>(dim1 * dim2, 0); 
        for (int i = 0; i < dim1 * dim2; ++i) B_1[i] = (B[i] - B_0[i]) % mod; 

        auto lastParmsID = context->lastParmsID();

        // initialize helper
        LinearHelper::MatmulHelper helper_0(dim0, dim1, dim2, slotCount, 0, packLwes);
        LinearHelper::MatmulHelper helper_1(dim0, dim1, dim2, slotCount, 1, packLwes);
        // printf("Matmul helper created\n");

        auto timer = Timer();
        auto t = timer.registerTimer("Matmul"); timer.tick(t);

        auto A_0_Encoded = helper_1.encodeInputs(*encoder, A_0.data());
        auto B_1_Encoded = helper_1.encodeWeights(*encoder, B_1.data());
        auto A_1_Encoded = helper_0.encodeInputs(*encoder, A_1.data());
        auto B_0_Encoded = helper_0.encodeWeights(*encoder, B_0.data());
        auto B_1_Enc = B_1_Encoded.encrypt(*encryptor);
        auto A_1_Enc = A_1_Encoded.encrypt(*encryptor);

        auto A_0_B_1_Enc = helper_1.matmulReverse(*evaluator, A_0_Encoded, B_1_Enc); 
        auto A_1_B_0_Enc = helper_0.matmul(*evaluator, A_1_Enc, B_0_Encoded); 

        A_0_B_1_Enc.modSwitchToNext(*evaluator);
        A_1_B_0_Enc.modSwitchToNext(*evaluator);

        if (packLwes) {
            A_0_B_1_Enc = helper_1.packOutputs(*evaluator, autok, A_0_B_1_Enc);
            A_1_B_0_Enc = helper_0.packOutputs(*evaluator, autok, A_1_B_0_Enc);
        }

        auto A_0_B_1_Dec = helper_1.decryptOutputs(*encoder, *decryptor, A_0_B_1_Enc);
        auto A_1_B_0_Dec = helper_0.decryptOutputs(*encoder, *decryptor, A_1_B_0_Enc);

        auto A_0_B_0 = plainMatMul(A_0, B_0, mod, dim0, dim1, dim2);
        auto A_1_B_1 = plainMatMul(A_1, B_1, mod, dim0, dim1, dim2);

        auto computed_C = std::vector<uint64_t>(dim0 * dim2, 0);
        for (size_t i = 0; i < dim0 * dim2; ++i) {
            computed_C[i] = (A_0_B_0[i] + A_1_B_1[i] + A_0_B_1_Dec[i] + A_1_B_0_Dec[i]) % mod;
        }

        auto C = plainMatMul(A, B, mod, dim0, dim1, dim2);
        
        timer.tock(t);
        printTimer(timer.gather());

        // comparison
        uint64_t diff = 0;
        for (size_t i = 0; i < dim0 * dim2; i++) {
            uint64_t d = std::abs<long long>(computed_C[i] - C[i]);
            if (d > diff) diff = d;
        }
        std::cout << "Difference = " << diff << std::endl;
        
    }

    void testMatmulInts(size_t batchSize, size_t inputDims, size_t outputDims, bool packLwes) {
        
        auto mod = parms.plainModulus().value();
        auto w = randomVector(inputDims * outputDims, mod);
        auto x = randomVector(inputDims * batchSize, mod);
        auto s = randomVector(batchSize * outputDims, mod);
        auto lastParmsID = context->lastParmsID();

        // initialize helper
        LinearHelper::MatmulHelper helper(batchSize, inputDims, outputDims, slotCount, 0, packLwes);
        // printf("Matmul helper created\n");

        auto wEncoded = helper.encodeWeights(*encoder, w.data());
        
        // for (size_t i = 0; i < wEncoded.data.size(); i++) {
        //     for (size_t j = 0; j < wEncoded.data[i].size(); j++) {
        //         std::cout << "w[" << i << "][" << j << "] = ";
        //         std::vector<uint64_t> v; encoder->decodePolynomial(wEncoded.data[i][j], v); 
        //         printVector(v);
        //     }
        // }

        // std::cout << "weight plaintext coeffcount = " << wEncoded[0][0].coeffCount() << std::endl;

        // interaction
        auto timer = Timer();
        auto t = timer.registerTimer("Matmul"); timer.tick(t);
        auto xEncoded = helper.encodeInputs(*encoder, x.data());
        auto xEnc = xEncoded.encrypt(*encryptor);

        { // serialize
            ostringstream sout; xEnc.save(sout);
            auto p = sout.str(); std::cout << "xEnc length = " << p.size() << std::endl;
            istringstream sin(p); xEnc = LinearHelper::Cipher2d();
            xEnc.load(sin, *context);
        }
        
        // for (size_t i = 0; i < xEnc.data.size(); i++) {
        //     for (size_t j = 0; j < xEnc.data[i].size(); j++) {
        //         std::cout << "xEnc[" << i << "][" << j << "] = ";
        //         Plaintext p; decryptor->decrypt(xEnc.data[i][j], p);
        //         std::vector<uint64_t> v; encoder->decodePolynomial(p, v); 
        //         printVector(v);
        //     }
        // }

        auto yEnc = helper.matmul(*evaluator, xEnc, wEncoded);  

        // printf("matmul\n");
        // for (size_t i = 0; i < yEnc.data.size(); i++) {
        //     for (size_t j = 0; j < yEnc.data[i].size(); j++) {
        //         std::cout << "yEnc[" << i << "][" << j << "] = ";
        //         Plaintext p; decryptor->decrypt(yEnc.data[i][j], p);
        //         std::vector<uint64_t> v; encoder->decodePolynomial(p, v); 
        //         printVector(v);
        //     }
        // }

        yEnc.modSwitchToNext(*evaluator); 
        
        // printf("switch to next\n");
        // for (size_t i = 0; i < yEnc.data.size(); i++) {
        //     for (size_t j = 0; j < yEnc.data[i].size(); j++) {
        //         std::cout << "yEnc[" << i << "][" << j << "] = ";
        //         Plaintext p; decryptor->decrypt(yEnc.data[i][j], p);
        //         std::vector<uint64_t> v; encoder->decodePolynomial(p, v); 
        //         printVector(v);
        //     }
        // }

        if (packLwes) {
            yEnc = helper.packOutputs(*evaluator, autok, yEnc);
            // printf("pack\n");
            // for (size_t i = 0; i < yEnc.data.size(); i++) {
            //     for (size_t j = 0; j < yEnc.data[i].size(); j++) {
            //         std::cout << "yEnc[" << i << "][" << j << "] = ";
            //         Plaintext p; decryptor->decrypt(yEnc.data[i][j], p);
            //         std::vector<uint64_t> v; encoder->decodePolynomial(p, v); 
            //         printVector(v);
            //     }
            // }
        }
        
        { // serialize
            ostringstream sout; helper.serializeOutputs(*evaluator, yEnc, sout);
            auto p = sout.str(); std::cout << "yEnc length = " << p.size() << std::endl;
            istringstream sin(p); 
            yEnc = helper.deserializeOutputs(*evaluator, sin);
        }
        
        // printf("Matmul done\n");

        auto yDec = helper.decryptOutputs(*encoder, *decryptor, yEnc);
        timer.tock(t);
        printTimer(timer.gather());

        // printf("Decrypted\n");
        
        // plaintext computation
        vector<uint64_t> y(batchSize * outputDims, 0);
        for (size_t i = 0; i < batchSize; i++) {
            for (size_t j = 0; j < inputDims; j++) {
                for (size_t k = 0; k < outputDims; k++) {
                    y[i * outputDims + k] += x[i * inputDims + j] * w[j * outputDims + k];
                    y[i * outputDims + k] %= mod;
                    
                }
            }
        }

        // printVector(y);
        // printVector(yDec);

        // comparison
        uint64_t diff = 0;
        for (size_t i = 0; i < batchSize * outputDims; i++) {
            uint64_t d = std::abs<long long>(y[i] - yDec[i]);
            if (d > diff) diff = d;
        }
        std::cout << "Difference = " << diff << std::endl;
        
    }

    void testMatmulReverseInts(size_t batchSize, size_t inputDims, size_t outputDims, bool packLwes) {
        
        auto mod = parms.plainModulus().value();
        auto w = randomVector(inputDims * outputDims, mod);
        auto x = randomVector(inputDims * batchSize, mod);
        auto s = randomVector(batchSize * outputDims, mod);
        auto lastParmsID = context->lastParmsID();

        // initialize helper
        LinearHelper::MatmulHelper helper(batchSize, inputDims, outputDims, slotCount, 1, packLwes);
        // printf("Matmul helper created\n");

        auto wEncoded = helper.encodeWeights(*encoder, w.data());
        auto wEnc = wEncoded.encrypt(*encryptor);

        // interaction
        auto timer = Timer();
        auto t = timer.registerTimer("Matmul"); timer.tick(t);
        auto xEncoded = helper.encodeInputs(*encoder, x.data());

        auto yEnc = helper.matmulReverse(*evaluator, xEncoded, wEnc);

        yEnc.modSwitchToNext(*evaluator); 

        if (packLwes) {
            yEnc = helper.packOutputs(*evaluator, autok, yEnc);
        }
        
        { // serialize
            ostringstream sout; helper.serializeOutputs(*evaluator, yEnc, sout);
            auto p = sout.str(); std::cout << "yEnc length = " << p.size() << std::endl;
            istringstream sin(p); 
            yEnc = helper.deserializeOutputs(*evaluator, sin);
        }
        
        // printf("Matmul done\n");

        auto yDec = helper.decryptOutputs(*encoder, *decryptor, yEnc);
        timer.tock(t);
        printTimer(timer.gather());

        // printf("Decrypted\n");
        
        // plaintext computation
        vector<uint64_t> y(batchSize * outputDims, 0);
        for (size_t i = 0; i < batchSize; i++) {
            for (size_t j = 0; j < inputDims; j++) {
                for (size_t k = 0; k < outputDims; k++) {
                    y[i * outputDims + k] += x[i * inputDims + j] * w[j * outputDims + k];
                    y[i * outputDims + k] %= mod;
                    
                }
            }
        }

        // printVector(y);
        // printVector(yDec);

        // comparison
        uint64_t diff = 0;
        for (size_t i = 0; i < batchSize * outputDims; i++) {
            uint64_t d = std::abs<long long>(y[i] - yDec[i]);
            if (d > diff) diff = d;
        }
        std::cout << "Difference = " << diff << std::endl;
        
    }

    void testConv2d(size_t batchSize, size_t inputChannels, size_t outputChannels, size_t imageHeight, size_t imageWidth, size_t kernelHeight, size_t kernelWidth) {
        
        // generate data
        auto weights = randomRealVector(inputChannels * outputChannels * kernelHeight * kernelWidth);
        auto x = randomRealVector(batchSize * inputChannels * imageHeight * imageWidth);
        auto lastParmsID = context->lastParmsID();

        // initialize helper
        LinearHelper::Conv2dHelper helper(batchSize, imageHeight, imageWidth, kernelHeight, kernelWidth, inputChannels, outputChannels, slotCount);
        auto encodedWeights = helper.encodeWeights(*encoder, getUint64(weights));

        auto tim = Timer();
        tim.registerTimer();
        tim.tick();
        // interaction
        auto xEnc = helper.encryptInputs(*encryptor, *encoder, getUint64(x));
        { // serialize
            ostringstream sout; xEnc.save(sout);
            auto p = sout.str(); std::cout << "xEnc length = " << p.size() << std::endl;
            istringstream sin(p); xEnc = LinearHelper::Cipher2d();
            xEnc.load(sin, *context);
        }
        auto yEnc = helper.conv2d(*evaluator, xEnc, encodedWeights);
        { // serialize
            ostringstream sout; helper.serializeOutputs(*evaluator, yEnc, sout);
            auto p = sout.str(); std::cout << "yEnc length = " << p.size() << std::endl;
            istringstream sin(p); 
            yEnc = helper.deserializeOutputs(*evaluator, sin);
        }

        // dec
        auto yDec = getDouble(helper.decryptOutputs(*encoder, *decryptor, yEnc), delta*delta);
        tim.tock();

        printTimer(tim.gather());

        printf("Plain...\n");
        
        // plaintext computation
        size_t yh = imageHeight - kernelHeight + 1, yw = imageWidth - kernelWidth + 1;
        vector<double> y(batchSize * outputChannels * yh * yw, 0);
        for (size_t b = 0; b < batchSize; b++) {
            for (size_t oc = 0; oc < outputChannels; oc++) {
                for (size_t yi = 0; yi < yh; yi++) {
                    for (size_t yj = 0; yj < yw; yj++) {
                        double element = 0;
                        for (size_t ic = 0; ic < inputChannels; ic++) {
                            for (size_t xi = yi; xi < yi + kernelHeight; xi++) {
                                for (size_t xj = yj; xj < yj + kernelWidth; xj++) {
                                    size_t xIndex = ((b * inputChannels + ic) * imageHeight + xi) * imageWidth + xj;
                                    size_t wIndex = ((oc * inputChannels + ic) * kernelHeight + (xi - yi)) * kernelWidth + (xj - yj);
                                    element += x[xIndex] * weights[wIndex];
                                }
                            }
                        }
                        y[((b * outputChannels + oc) * yh + yi) * yw + yj] = element;
                    }
                }
            }
        }

        // printVector(y);
        // printVector(yDec);

        // comparison
        double diff = 0;
        double reldiff = 0;
        for (size_t i = 0; i < y.size(); i++) {
            double d = std::abs(y[i] - yDec[i]);
            double reld = d / std::abs(y[i]);
            if (d > diff) diff = d;
            if (reld > reldiff) {
                reldiff = reld;
            }
        }
        std::cout << "Difference = " << diff << " relative = " << reldiff << std::endl;
        
    }



    void testConv2dInt(size_t batchSize, size_t inputChannels, size_t outputChannels, size_t imageHeight, size_t imageWidth, size_t kernelHeight, size_t kernelWidth) {
        
        // generate data
        auto weights = randomVector(inputChannels * outputChannels * kernelHeight * kernelWidth);
        auto x = randomVector(batchSize * inputChannels * imageHeight * imageWidth);
        size_t yh = imageHeight - kernelHeight + 1, yw = imageWidth - kernelWidth + 1;
        vector<uint64_t> s = randomVector(batchSize * outputChannels * yh * yw);

        // weights = {
        //     1, 2, 3, 4, 5, 6, 7, 8, 9, 
        // };

        // x = {
        //      1, 2, 3, 0, 0,
        //      6, 7, 8, 0, 0,
        //     11,12,13, 0, 0,
        //      0, 0, 0, 0, 0,
        //      0, 0, 0, 0, 0,
        //     11,12,13, 0, 0,
        //      1, 2, 3, 0, 0,
        //      6, 7, 8, 0, 0,
        //      0, 0, 0, 0, 0,
        //      0, 0, 0, 0, 0,
        // };

        auto lastParmsID = context->lastParmsID();
        auto mod = parms.plainModulus().value();

        // initialize helper
        std::cout << "Creating helper" << std::endl;
        LinearHelper::Conv2dHelper helper(batchSize, imageHeight, imageWidth, kernelHeight, kernelWidth, inputChannels, outputChannels, slotCount);
        std::cout << "Helper created" << std::endl;
        auto encodedWeights = helper.encodeWeights(*encoder, weights);
        std::cout << "Weights encoded" << std::endl;

        auto sEncoded = helper.encodeOutputs(*encoder, s);

        // for (size_t i = 0; i < encodedWeights.data.size(); i++) {
        //     for (size_t j = 0; j < encodedWeights.data[i].size(); j++) {
        //         std::cout << "wEnc[" << i << "][" << j << "] = ";
        //         std::vector<uint64_t> v; encoder->decodePolynomial(encodedWeights.data[i][j], v); 
        //         printVector(v, 50);
        //     }
        // }

        auto tim = Timer();
        tim.registerTimer();
        tim.tick();
        // interaction
        auto xEnc = helper.encryptInputs(*encryptor, *encoder, x);

        // for (size_t i = 0; i < xEnc.data.size(); i++) {
        //     for (size_t j = 0; j < xEnc.data[i].size(); j++) {
        //         std::cout << "xEnc[" << i << "][" << j << "] = ";
        //         Plaintext p; decryptor->decrypt(xEnc.data[i][j], p);
        //         std::vector<uint64_t> v; encoder->decodePolynomial(p, v); 
        //         printVector(v, 50);
        //     }
        // }

        { // serialize
            ostringstream sout; xEnc.save(sout);
            auto p = sout.str(); std::cout << "xEnc length = " << p.size() << std::endl;
            istringstream sin(p); xEnc = LinearHelper::Cipher2d();
            xEnc.load(sin, *context);
        }

        auto yEnc = helper.conv2d(*evaluator, xEnc, encodedWeights);
        printf("yEnc.size() = %lu, yEnc.data[0].size() = %lu\n", yEnc.data.size(), yEnc.data[0].size());
        printf("sEnc.size() = %lu, sEnc.data[0].size() = %lu\n", sEncoded.data.size(), sEncoded.data[0].size());
        yEnc.addPlainInplace(*evaluator, sEncoded);
        
        { // serialize
            ostringstream sout; helper.serializeOutputs(*evaluator, yEnc, sout);
            auto p = sout.str(); std::cout << "yEnc length = " << p.size() << std::endl;
            istringstream sin(p); 
            yEnc = helper.deserializeOutputs(*evaluator, sin);
        }

        // for (size_t i = 0; i < yEnc.data.size(); i++) {
        //     for (size_t j = 0; j < yEnc.data[i].size(); j++) {
        //         std::cout << "yEnc[" << i << "][" << j << "] = ";
        //         Plaintext p; decryptor->decrypt(yEnc.data[i][j], p);
        //         std::vector<uint64_t> v; encoder->decodePolynomial(p, v); 
        //         printVector(v, 50);
        //     }
        // }

        // dec
        auto yDec = helper.decryptOutputs(*encoder, *decryptor, yEnc);
        // std::cout << "yDec = ";
        // printVector(yDec, 50);
        tim.tock();

        printTimer(tim.gather());

        printf("Plain...\n");
        
        // plaintext computation
        vector<uint64_t> y(batchSize * outputChannels * yh * yw, 0);
        for (size_t b = 0; b < batchSize; b++) {
            for (size_t oc = 0; oc < outputChannels; oc++) {
                for (size_t yi = 0; yi < yh; yi++) {
                    for (size_t yj = 0; yj < yw; yj++) {
                        uint64_t element = s[((b * outputChannels + oc) * yh + yi) * yw + yj];
                        for (size_t ic = 0; ic < inputChannels; ic++) {
                            for (size_t xi = yi; xi < yi + kernelHeight; xi++) {
                                for (size_t xj = yj; xj < yj + kernelWidth; xj++) {
                                    size_t xIndex = ((b * inputChannels + ic) * imageHeight + xi) * imageWidth + xj;
                                    size_t wIndex = ((oc * inputChannels + ic) * kernelHeight + (xi - yi)) * kernelWidth + (xj - yj);
                                    element += (x[xIndex] * weights[wIndex]) % mod;
                                }
                            }
                        }
                        y[((b * outputChannels + oc) * yh + yi) * yw + yj] = element;
                    }
                }
            }
        }

        // printVector(y);
        // printVector(yDec);
        // std::cout << "y = ";
        // printVector(y, 50);

        // comparison
        uint64_t diff = 0;
        for (size_t i = 0; i < y.size(); i++) {
            uint64_t d = std::abs<long long>(y[i] - yDec[i]);
            if (d > diff) diff = d;
        }
        std::cout << "Difference = " << diff << std::endl;
        
    }

};

int main() {
    KernelProvider::initialize();
    srand(0);
    LinearTest test(8192, {60, 60, 60}, 16, 1ul<<32, 1ul<<8);
    printf("Setup\n");
    // test.testMatmulInts(4, 6, 8, false);
    // test.testMatmulInts(128, 500, 1001, false);
    // test.testMatmulReverseInts(128, 300, 1001, true);
    // test.testConv2d(1, 64, 256, 56, 56, 3, 3);
    // test.testConv2dInt(4, 64, 256, 56, 56, 3, 3);

    test.test_ss_MatmulInts(128, 300, 1001, true);
    test.test_ss_Encode(1000);
}