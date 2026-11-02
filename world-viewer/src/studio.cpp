#include "studio.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

#include "keyvalues.hpp"
#include "scene.hpp"

namespace zmv {

namespace {

// Bounds-checked little-endian reader over one file's bytes.
struct Blob {
    const std::string& data;
    bool ok = true;
    template <typename T>
    T Get(size_t offset) {
        T v{};
        if (offset + sizeof(T) > data.size()) {
            ok = false;
            return v;
        }
        std::memcpy(&v, data.data() + offset, sizeof(T));
        return v;
    }
    std::string CString(size_t offset) {
        if (offset >= data.size()) {
            ok = false;
            return {};
        }
        const size_t end = data.find('\0', offset);
        return data.substr(offset, (end == std::string::npos ? data.size() : end) - offset);
    }
};

std::string Normalize(std::string s) {
    std::replace(s.begin(), s.end(), '\\', '/');
    s = ToLower(s);
    while (!s.empty() && s.front() == '/') s.erase(s.begin());
    size_t pos;
    while ((pos = s.find("//")) != std::string::npos) s.erase(pos, 1);
    return s;
}

struct StudioVertex {
    float weight[3];
    uint8_t bone[3];
    uint8_t numBones;
    float pos[3];
    float normal[3];
    float uv[2];
};

constexpr size_t kVvdVertexSize = 48;
constexpr size_t kMdlTextureSize = 64;
constexpr size_t kMdlBodyPartSize = 16;
constexpr size_t kMdlModelSize = 148;
constexpr size_t kMdlMeshSize = 116;
constexpr size_t kVtxVertexSize = 9;

bool ReadVvd(const std::string& bytes, std::vector<StudioVertex>& out, std::string& error) {
    Blob b{bytes};
    if (bytes.size() < 64 || bytes.compare(0, 4, "IDSV") != 0) {
        error = "bad vvd header";
        return false;
    }
    const int lod0 = b.Get<int32_t>(16);
    const int numFixups = b.Get<int32_t>(48);
    const int fixupStart = b.Get<int32_t>(52);
    const int vertexStart = b.Get<int32_t>(56);
    auto readVertex = [&](int index) {
        const size_t o = static_cast<size_t>(vertexStart) + static_cast<size_t>(index) * kVvdVertexSize;
        StudioVertex v{};
        for (int k = 0; k < 3; ++k) v.weight[k] = b.Get<float>(o + k * 4);
        for (int k = 0; k < 3; ++k) v.bone[k] = b.Get<uint8_t>(o + 12 + k);
        v.numBones = b.Get<uint8_t>(o + 15);
        for (int k = 0; k < 3; ++k) v.pos[k] = b.Get<float>(o + 16 + k * 4);
        for (int k = 0; k < 3; ++k) v.normal[k] = b.Get<float>(o + 28 + k * 4);
        v.uv[0] = b.Get<float>(o + 40);
        v.uv[1] = b.Get<float>(o + 44);
        return v;
    };
    if (lod0 <= 0 || lod0 > 1000000) {
        error = "bad vvd vertex count";
        return false;
    }
    out.clear();
    out.reserve(static_cast<size_t>(lod0));
    if (numFixups <= 0) {
        for (int i = 0; i < lod0; ++i) out.push_back(readVertex(i));
    } else {
        // Fixups rebuild the per-LOD vertex order; every fixup applies to LOD0.
        for (int f = 0; f < numFixups && b.ok; ++f) {
            const size_t o = static_cast<size_t>(fixupStart) + static_cast<size_t>(f) * 12;
            const int lod = b.Get<int32_t>(o);
            const int source = b.Get<int32_t>(o + 4);
            const int count = b.Get<int32_t>(o + 8);
            if (lod < 0) continue;
            for (int i = 0; i < count; ++i) out.push_back(readVertex(source + i));
        }
    }
    if (!b.ok) {
        error = "truncated vvd";
        return false;
    }
    return true;
}

struct MeshRef {
    int material = 0;
    int vertexBase = 0;  // first VVD vertex of this mesh
};

// Row-major 3x4 affine matrix, matching the SDK's matrix3x4_t.
struct M34 {
    double m[3][4] = {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}};
};

M34 Mul(const M34& a, const M34& b) {
    M34 r;
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j < 4; ++j) {
            r.m[i][j] = a.m[i][0] * b.m[0][j] + a.m[i][1] * b.m[1][j] + a.m[i][2] * b.m[2][j] + (j == 3 ? a.m[i][3] : 0);
        }
    }
    return r;
}

struct Quat {
    double x = 0, y = 0, z = 0, w = 1;
};

// SDK QuaternionMatrix + translation.
M34 QuatMatrix(const Quat& q, const double pos[3]) {
    M34 r;
    r.m[0][0] = 1 - 2 * q.y * q.y - 2 * q.z * q.z;
    r.m[1][0] = 2 * q.x * q.y + 2 * q.w * q.z;
    r.m[2][0] = 2 * q.x * q.z - 2 * q.w * q.y;
    r.m[0][1] = 2 * q.x * q.y - 2 * q.w * q.z;
    r.m[1][1] = 1 - 2 * q.x * q.x - 2 * q.z * q.z;
    r.m[2][1] = 2 * q.y * q.z + 2 * q.w * q.x;
    r.m[0][2] = 2 * q.x * q.z + 2 * q.w * q.y;
    r.m[1][2] = 2 * q.y * q.z - 2 * q.w * q.x;
    r.m[2][2] = 1 - 2 * q.x * q.x - 2 * q.y * q.y;
    for (int i = 0; i < 3; ++i) r.m[i][3] = pos[i];
    return r;
}

// SDK AngleQuaternion(RadianEuler).
Quat EulerQuat(const double a[3]) {
    const double sr = std::sin(a[0] * 0.5), cr = std::cos(a[0] * 0.5);
    const double sp = std::sin(a[1] * 0.5), cp = std::cos(a[1] * 0.5);
    const double sy = std::sin(a[2] * 0.5), cy = std::cos(a[2] * 0.5);
    const double srXcp = sr * cp, crXsp = cr * sp, crXcp = cr * cp, srXsp = sr * sp;
    return {srXcp * cy - crXsp * sy, crXsp * cy + srXcp * sy, crXcp * sy - srXsp * cy, crXcp * cy + srXsp * sy};
}

double Half(uint16_t h) {
    const int exponent = (h >> 10) & 0x1f;
    const int mantissa = h & 0x3ff;
    double v;
    if (exponent == 0) v = std::ldexp(mantissa, -24);
    else if (exponent == 31) v = 0;  // inf/nan never appear in valid positions
    else v = std::ldexp(mantissa + 1024, exponent - 25);
    return (h & 0x8000) ? -v : v;
}

struct BoneInfo {
    std::string name;
    int parent = -1;
    double pos[3] = {};
    Quat quat;
    double rot[3] = {};
    double posScale[3] = {};
    double rotScale[3] = {};
    M34 poseToBone;
};

constexpr size_t kMdlBoneSize = 216;
constexpr size_t kMdlSeqSize = 212;
constexpr size_t kMdlAnimDescSize = 100;
constexpr int kStudioHdrStaticProp = 0x10;
constexpr int kAnimDescDelta = 0x4;
constexpr int kAnimRawPos = 0x01, kAnimRawRot = 0x02, kAnimAnimPos = 0x04, kAnimAnimRot = 0x08, kAnimDelta = 0x10,
              kAnimRawRot2 = 0x20;

// Frame 0 of the first local sequence's first animation, overriding each animated bone's default
// pos/quat. Returns a description of what was applied; external (.ani) or delta data is skipped.
std::string ApplyFirstSequenceFrame(Blob& m, std::vector<BoneInfo>& bones) {
    const int numSeq = m.Get<int32_t>(188);
    const int seqIndex = m.Get<int32_t>(192);
    const int numAnim = m.Get<int32_t>(180);
    const int animIndex = m.Get<int32_t>(184);
    if (numSeq <= 0 || numAnim <= 0) return "no local sequence";
    const size_t seq = static_cast<size_t>(seqIndex);
    const std::string seqName = m.CString(seq + static_cast<size_t>(m.Get<int32_t>(seq + 4)));
    const int anim = m.Get<int16_t>(seq + static_cast<size_t>(m.Get<int32_t>(seq + 60)));
    if (anim < 0 || anim >= numAnim) return "seq '" + seqName + "' anim out of range";
    const size_t desc = static_cast<size_t>(animIndex) + static_cast<size_t>(anim) * kMdlAnimDescSize;
    const std::string animName = m.CString(desc + static_cast<size_t>(m.Get<int32_t>(desc + 4)));
    const std::string label = "seq '" + seqName + "' anim '" + animName + "'";
    if (m.Get<int32_t>(desc + 12) & kAnimDescDelta) return label + " is delta (default pose)";
    int block = m.Get<int32_t>(desc + 52);
    size_t data = desc + static_cast<size_t>(m.Get<int32_t>(desc + 56));
    if (m.Get<int32_t>(desc + 84) > 0) {  // sectioned: frame 0 lives in section 0
        const size_t section = desc + static_cast<size_t>(m.Get<int32_t>(desc + 80));
        block = m.Get<int32_t>(section);
        data = desc + static_cast<size_t>(m.Get<int32_t>(section + 4));
    }
    if (block != 0) return label + " external block (default pose)";
    int applied = 0;
    for (int guard = 0; guard < 1024 && m.ok; ++guard) {
        const int bone = m.Get<uint8_t>(data);
        const int flags = m.Get<uint8_t>(data + 1);
        const int next = m.Get<int16_t>(data + 2);
        const size_t payload = data + 4;
        if (bone < static_cast<int>(bones.size()) && !(flags & kAnimDelta)) {
            BoneInfo& b = bones[static_cast<size_t>(bone)];
            if (flags & kAnimRawRot) {
                const uint16_t x = m.Get<uint16_t>(payload), y = m.Get<uint16_t>(payload + 2),
                               zw = m.Get<uint16_t>(payload + 4);
                Quat q{(x - 32768) / 32768.0, (y - 32768) / 32768.0, ((zw & 0x7fff) - 16384) / 16384.0, 0};
                q.w = std::sqrt(std::max(0.0, 1 - q.x * q.x - q.y * q.y - q.z * q.z));
                if (zw & 0x8000) q.w = -q.w;
                b.quat = q;
            } else if (flags & kAnimRawRot2) {
                const uint64_t v = m.Get<uint64_t>(payload);
                Quat q{((v & 0x1fffff) - 1048576.0) / 1048576.5, (((v >> 21) & 0x1fffff) - 1048576.0) / 1048576.5,
                       (((v >> 42) & 0x1fffff) - 1048576.0) / 1048576.5, 0};
                q.w = std::sqrt(std::max(0.0, 1 - q.x * q.x - q.y * q.y - q.z * q.z));
                if (v >> 63) q.w = -q.w;
                b.quat = q;
            } else if (flags & kAnimAnimRot) {
                double euler[3];
                for (int k = 0; k < 3; ++k) {
                    const int offset = m.Get<int16_t>(payload + static_cast<size_t>(k) * 2);
                    const double value =
                        offset > 0 ? m.Get<int16_t>(payload + static_cast<size_t>(offset) + 2) : 0.0;
                    euler[k] = value * b.rotScale[k] + b.rot[k];
                }
                b.quat = EulerQuat(euler);
            }
            if (flags & kAnimRawPos) {
                const size_t p = payload + ((flags & kAnimRawRot) ? 6 : 0) + ((flags & kAnimRawRot2) ? 8 : 0);
                for (int k = 0; k < 3; ++k) b.pos[k] = Half(m.Get<uint16_t>(p + static_cast<size_t>(k) * 2));
            } else if (flags & kAnimAnimPos) {
                const size_t p = payload + ((flags & kAnimAnimRot) ? 6 : 0);
                for (int k = 0; k < 3; ++k) {
                    const int offset = m.Get<int16_t>(p + static_cast<size_t>(k) * 2);
                    const double value = offset > 0 ? m.Get<int16_t>(p + static_cast<size_t>(offset) + 2) : 0.0;
                    b.pos[k] = value * b.posScale[k] + b.pos[k];
                }
            }
            ++applied;
        }
        if (next <= 0) break;
        data += static_cast<size_t>(next);
    }
    return label + ", " + std::to_string(applied) + " animated bones";
}

// Bone-to-model skinning matrices for frame 0 of the first sequence (bone->world * pose->bone).
// Returns false when the model needs no posing.
bool BuildSkinning(Blob& m, std::vector<M34>& skin, std::string& info) {
    const int flags = m.Get<int32_t>(152);
    const int numBones = m.Get<int32_t>(156);
    const int boneIndex = m.Get<int32_t>(160);
    char head[64];
    std::snprintf(head, sizeof(head), "flags 0x%x, %d bones", flags, numBones);
    info = head;
    if (flags & kStudioHdrStaticProp) {
        info += ", $staticprop (baked)";
        return false;
    }
    if (numBones <= 0 || numBones > 256) return false;
    std::vector<BoneInfo> bones(static_cast<size_t>(numBones));
    for (int i = 0; i < numBones && m.ok; ++i) {
        const size_t o = static_cast<size_t>(boneIndex) + static_cast<size_t>(i) * kMdlBoneSize;
        BoneInfo& b = bones[static_cast<size_t>(i)];
        b.name = m.CString(o + static_cast<size_t>(m.Get<int32_t>(o)));
        b.parent = m.Get<int32_t>(o + 4);
        for (int k = 0; k < 3; ++k) {
            b.pos[k] = m.Get<float>(o + 32 + k * 4);
            b.rot[k] = m.Get<float>(o + 60 + k * 4);
            b.posScale[k] = m.Get<float>(o + 72 + k * 4);
            b.rotScale[k] = m.Get<float>(o + 84 + k * 4);
        }
        b.quat = {m.Get<float>(o + 44), m.Get<float>(o + 48), m.Get<float>(o + 52), m.Get<float>(o + 56)};
        for (int r = 0; r < 3; ++r)
            for (int c = 0; c < 4; ++c) b.poseToBone.m[r][c] = m.Get<float>(o + 96 + (r * 4 + c) * 4);
    }
    if (!m.ok) return false;
    info += ", " + ApplyFirstSequenceFrame(m, bones);
    std::vector<M34> boneToModel(bones.size());
    skin.assign(bones.size(), M34{});
    double maxDeviation = 0;
    for (size_t i = 0; i < bones.size(); ++i) {
        const M34 local = QuatMatrix(bones[i].quat, bones[i].pos);
        const int parent = bones[i].parent;
        boneToModel[i] = (parent >= 0 && parent < static_cast<int>(i)) ? Mul(boneToModel[static_cast<size_t>(parent)], local)
                                                                       : local;
        skin[i] = Mul(boneToModel[i], bones[i].poseToBone);
        for (int r = 0; r < 3; ++r)
            for (int c = 0; c < 4; ++c)
                maxDeviation = std::max(maxDeviation, std::abs(skin[i].m[r][c] - (r == c ? 1.0 : 0.0)) * (c == 3 ? 0.01 : 1.0));
    }
    char tail[96];
    std::snprintf(tail, sizeof(tail), ", root '%s', pose deviation %.4f", bones[0].name.c_str(), maxDeviation);
    info += tail;
    return maxDeviation > 1e-4;
}

void SkinVertices(std::vector<StudioVertex>& verts, const std::vector<M34>& skin) {
    for (StudioVertex& v : verts) {
        double p[3] = {}, n[3] = {};
        const int count = std::clamp<int>(v.numBones, 1, 3);
        double total = 0;
        for (int k = 0; k < count; ++k) {
            const size_t bone = v.bone[k];
            if (bone >= skin.size()) continue;
            const double w = v.numBones == 0 ? 1.0 : v.weight[k];
            const M34& s = skin[bone];
            for (int r = 0; r < 3; ++r) {
                p[r] += w * (s.m[r][0] * v.pos[0] + s.m[r][1] * v.pos[1] + s.m[r][2] * v.pos[2] + s.m[r][3]);
                n[r] += w * (s.m[r][0] * v.normal[0] + s.m[r][1] * v.normal[1] + s.m[r][2] * v.normal[2]);
            }
            total += w;
        }
        if (total <= 1e-6) continue;
        const double len = std::sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
        for (int r = 0; r < 3; ++r) {
            v.pos[r] = static_cast<float>(p[r] / total);
            if (len > 1e-9) v.normal[r] = static_cast<float>(n[r] / len);
        }
    }
}

}  // namespace

bool LoadStudioModel(const GameFileSystem& fs, MaterialColors& colors, const std::string& modelPath, int skin,
                     StudioLoadResult& out) {
    std::string path = Normalize(modelPath);
    if (path.size() < 4 || path.compare(path.size() - 4, 4, ".mdl") != 0) {
        out.error = "not an .mdl path: " + modelPath;
        return false;
    }
    const std::string base = path.substr(0, path.size() - 4);
    std::string mdl, vvd, vtx;
    if (!fs.Read(path, mdl)) {
        out.error = "missing " + path;
        return false;
    }
    if (!fs.Read(base + ".vvd", vvd)) {
        out.error = "missing " + base + ".vvd";
        return false;
    }
    if (!fs.Read(base + ".dx90.vtx", vtx) && !fs.Read(base + ".vtx", vtx)) {
        out.error = "missing " + base + ".dx90.vtx";
        return false;
    }
    out.hash = Fnv1a(vtx, Fnv1a(vvd, Fnv1a(mdl)));

    Blob m{mdl};
    if (mdl.size() < 240 || mdl.compare(0, 4, "IDST") != 0) {
        out.error = "bad mdl header: " + path;
        return false;
    }
    const int numTextures = m.Get<int32_t>(204);
    const int textureIndex = m.Get<int32_t>(208);
    const int numCd = m.Get<int32_t>(212);
    const int cdIndex = m.Get<int32_t>(216);
    const int numSkinRef = m.Get<int32_t>(220);
    const int numSkinFamilies = m.Get<int32_t>(224);
    const int skinIndex = m.Get<int32_t>(228);
    const int numBodyParts = m.Get<int32_t>(232);
    const int bodyPartIndex = m.Get<int32_t>(236);

    std::vector<std::string> textures;
    for (int i = 0; i < numTextures && m.ok && i < 4096; ++i) {
        const size_t o = static_cast<size_t>(textureIndex) + static_cast<size_t>(i) * kMdlTextureSize;
        textures.push_back(Normalize(m.CString(o + static_cast<size_t>(m.Get<int32_t>(o)))));
    }
    std::vector<std::string> cdPaths;
    for (int i = 0; i < numCd && m.ok && i < 64; ++i) {
        cdPaths.push_back(Normalize(m.CString(static_cast<size_t>(m.Get<int32_t>(static_cast<size_t>(cdIndex) + i * 4)))));
    }
    if (cdPaths.empty()) cdPaths.push_back("");
    const int family = (skin >= 0 && skin < numSkinFamilies) ? skin : 0;
    auto skinTexture = [&](int ref) {
        if (ref < 0 || ref >= numSkinRef || numSkinFamilies <= 0) return ref;
        const size_t o = static_cast<size_t>(skinIndex) + (static_cast<size_t>(family) * numSkinRef + ref) * 2;
        return static_cast<int>(m.Get<int16_t>(o));
    };

    // Resolve each texture against the cdmaterials search paths once.
    std::vector<const MaterialInfo*> materials(textures.size(), nullptr);
    auto material = [&](int tex) -> const MaterialInfo* {
        if (tex < 0 || tex >= static_cast<int>(textures.size())) return nullptr;
        if (!materials[tex]) {
            std::string chosen = cdPaths.front() + textures[tex];
            std::string probe;
            for (const std::string& cd : cdPaths) {
                if (fs.Read("materials/" + cd + textures[tex] + ".vmt", probe, 1)) {
                    chosen = cd + textures[tex];
                    break;
                }
            }
            materials[tex] = &colors.Info(chosen);
        }
        return materials[tex];
    };

    std::vector<StudioVertex> verts;
    if (!ReadVvd(vvd, verts, out.error)) {
        out.error += ": " + path;
        return false;
    }
    {
        Blob bonesBlob{mdl};
        std::vector<M34> skinning;
        const bool posed = BuildSkinning(bonesBlob, skinning, out.poseInfo);
        if (!bonesBlob.ok) out.poseInfo += " (truncated bone data, unposed)";
        else if (posed) {
            SkinVertices(verts, skinning);
            out.poseInfo += ", posed";
        }
    }

    // Body parts -> first model -> meshes, mirrored by the VTX hierarchy.
    std::vector<std::vector<MeshRef>> parts;
    for (int bp = 0; bp < numBodyParts && m.ok && bp < 256; ++bp) {
        const size_t bpo = static_cast<size_t>(bodyPartIndex) + static_cast<size_t>(bp) * kMdlBodyPartSize;
        const int numModels = m.Get<int32_t>(bpo + 4);
        const int modelIndex = m.Get<int32_t>(bpo + 12);
        std::vector<MeshRef> meshes;
        if (numModels > 0) {
            const size_t mo = bpo + static_cast<size_t>(modelIndex);
            const int numMeshes = m.Get<int32_t>(mo + 72);
            const int meshIndex = m.Get<int32_t>(mo + 76);
            const int vertexIndex = m.Get<int32_t>(mo + 84);
            for (int k = 0; k < numMeshes && m.ok && k < 1024; ++k) {
                const size_t meo = mo + static_cast<size_t>(meshIndex) + static_cast<size_t>(k) * kMdlMeshSize;
                MeshRef ref;
                ref.material = m.Get<int32_t>(meo);
                ref.vertexBase = vertexIndex / static_cast<int>(kVvdVertexSize) + m.Get<int32_t>(meo + 12);
                meshes.push_back(ref);
            }
        }
        parts.push_back(std::move(meshes));
    }
    if (!m.ok) {
        out.error = "truncated mdl: " + path;
        return false;
    }

    // Strip groups are 25 bytes in the SDK 2013 VTX layout; some newer compilers append two ints.
    for (const size_t stripGroupSize : {size_t{25}, size_t{33}}) {
        Blob v{vtx};
        MeshData mesh;
        bool valid = vtx.size() >= 36;
        const int vtxBodyParts = v.Get<int32_t>(28);
        const int vtxBodyPartOffset = v.Get<int32_t>(32);
        for (int bp = 0; valid && bp < vtxBodyParts && bp < static_cast<int>(parts.size()); ++bp) {
            const size_t bpo = static_cast<size_t>(vtxBodyPartOffset) + static_cast<size_t>(bp) * 8;
            if (v.Get<int32_t>(bpo) <= 0) continue;
            const size_t mo = bpo + static_cast<size_t>(v.Get<int32_t>(bpo + 4));
            if (v.Get<int32_t>(mo) <= 0) continue;
            const size_t lo = mo + static_cast<size_t>(v.Get<int32_t>(mo + 4));  // LOD0
            const int numMeshes = v.Get<int32_t>(lo);
            const size_t meshBase = lo + static_cast<size_t>(v.Get<int32_t>(lo + 4));
            for (int k = 0; valid && k < numMeshes && k < static_cast<int>(parts[bp].size()); ++k) {
                const size_t meo = meshBase + static_cast<size_t>(k) * 9;
                const int numGroups = v.Get<int32_t>(meo);
                const size_t groupBase = meo + static_cast<size_t>(v.Get<int32_t>(meo + 4));
                const MeshRef& ref = parts[bp][k];
                const MaterialInfo* info = material(skinTexture(ref.material));
                const MaterialInfo fallback;
                const MaterialInfo& mat = info ? *info : fallback;
                for (int g = 0; valid && g < numGroups && g < 64; ++g) {
                    const size_t go = groupBase + static_cast<size_t>(g) * stripGroupSize;
                    const int numVerts = v.Get<int32_t>(go);
                    const size_t vertOffset = go + static_cast<size_t>(v.Get<int32_t>(go + 4));
                    const int numIndices = v.Get<int32_t>(go + 8);
                    const size_t indexOffset = go + static_cast<size_t>(v.Get<int32_t>(go + 12));
                    if (numVerts < 0 || numIndices < 0 || numIndices % 3 != 0) { valid = false; break; }
                    for (int i = 0; i < numIndices && v.ok; ++i) {
                        const int local = v.Get<uint16_t>(indexOffset + static_cast<size_t>(i) * 2);
                        if (local >= numVerts) { valid = false; break; }
                        const int orig = v.Get<uint16_t>(vertOffset + static_cast<size_t>(local) * kVtxVertexSize + 4);
                        const int index = ref.vertexBase + orig;
                        if (index < 0 || index >= static_cast<int>(verts.size())) { valid = false; break; }
                        const StudioVertex& sv = verts[index];
                        const double p[3] = {sv.pos[0], sv.pos[1], sv.pos[2]};
                        const double n[3] = {sv.normal[0], sv.normal[1], sv.normal[2]};
                        mesh.AddVertex(p, n, mat.color, sv.uv[0], sv.uv[1], mat.tile, mat.alpha);
                    }
                }
            }
        }
        if (valid && v.ok) {
            out.mesh = std::move(mesh);
            if (out.mesh.TriangleCount() == 0) {
                out.error = "no triangles: " + path;
                return false;
            }
            return true;
        }
    }
    out.error = "unreadable vtx: " + path;
    return false;
}

}  // namespace zmv
