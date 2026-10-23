#pragma once
#import "cheat_data.h"

class RecoilControl {
public:
    void Update();

private:
    bool m_patched = false;
    bool m_dumped = false;
    double m_last = 0;
};

RecoilControl* GetRecoilControl();
